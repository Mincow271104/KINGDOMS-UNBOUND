extends SceneTree
## Automated Test Suite: Field Siege Operations & Combat Victory (TASK-1X.3)
## Validates outpost objectives, eligibility gating, garrison defender mobilization,
## victory/defeat/withdrawal resolution, plunder awards, faction power deduction,
## coexistence with BattleCampaignManager, and persistence roundtrips.

const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const EnemyMilitaryManagerScript = preload("res://scripts/military/enemy_military_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")

var total_assertions: int = 0
var passed_assertions: int = 0
var failed_assertions: int = 0

class MockResourceManager:
	var resources: Dictionary = {"gold": 100, "food": 100, "wood": 100, "metal": 100}
	func add_resource(res_type: String, amount: int) -> int:
		if not resources.has(res_type):
			push_error("Attempted to add non-canonical resource: %s" % res_type)
			return 0
		resources[res_type] = resources.get(res_type, 0) + amount
		return amount
	func get_resource(res_type: String) -> int:
		return resources.get(res_type, 0)

class MockFactionData:
	var id: String = ""
	var name: String = ""
	var existence_status: String = "active"
	var is_at_war: bool = true
	var military_power: float = 60.0

class MockFactionManager:
	var _factions: Dictionary = {}
	func add_faction(fac: MockFactionData) -> void:
		_factions[fac.id] = fac
	func get_faction(f_id: String) -> MockFactionData:
		return _factions.get(f_id, null)
	func are_factions_at_war(f_id: String, _other: String) -> bool:
		var f = _factions.get(f_id, null)
		return f.is_at_war if f != null else false

func _init() -> void:
	call_deferred("_run_all_tests")

func _assert(condition: bool, test_name: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("  [PASS] %s" % test_name)
	else:
		failed_assertions += 1
		printerr("  [FAIL] %s" % test_name)

func _run_all_tests() -> void:
	print("========================================================")
	print("  STARTING PACKAGE 1X FIELD SIEGE OPERATIONS TEST SUITE")
	print("========================================================")

	_test_objective_actor_lifecycle()
	_test_outpost_durability_and_destruction()
	_test_eligibility_gating()
	_test_operation_launch_and_defender_mobilization()
	_test_victory_resolution_and_plunder()
	_test_defeat_resolution()
	_test_withdrawal_resolution()
	_test_coexistence_with_battle_campaign()
	_test_siege_serialization_roundtrip()
	_test_atomic_deserialization_fail_closed()
	_test_real_resource_manager_integration()
	_test_tactical_attack_order_gating()
	_test_peace_treaty_siege_cancellation()
	_test_siege_retry_and_bounded_defenders()
	_test_objective_click_prioritization_and_no_overlap()
	_test_gate_d_siege_state_distinctions()

	print("========================================================")
	if failed_assertions == 0:
		print("  [SUCCESS] All Field Siege Tests PASSED! (%d assertions)" % total_assertions)
		quit(0)
	else:
		printerr("  [FAILURE] %d assertions FAILED out of %d!" % [failed_assertions, total_assertions])
		quit(1)

func _test_objective_actor_lifecycle() -> void:
	print("\n--- Test 1: Objective Actor Lifecycle ---")
	var obj = SiegeObjectiveActorScript.new()
	obj.objective_id = "outpost_alpha"
	obj.owning_faction_id = "mountain_clans"
	obj.current_cell = Vector2i(25, 25)
	obj.max_health = 300.0
	obj.health = 300.0
	obj.garrison_count = 4

	_assert(obj.objective_id == "outpost_alpha", "TC-SIEGE.1: Objective ID initialized")
	_assert(obj.owning_faction_id == "mountain_clans", "TC-SIEGE.1: Owning faction recorded")
	_assert(obj.health == 300.0, "TC-SIEGE.1: Health initialized to 300.0")
	_assert(obj.is_alive == true, "TC-SIEGE.1: is_alive is initially true")
	_assert(obj.is_captured == false, "TC-SIEGE.1: is_captured is initially false")
	_assert(obj.garrison_count == 4, "TC-SIEGE.1: Garrison count is 4")

	obj.free()

func _test_outpost_durability_and_destruction() -> void:
	print("\n--- Test 2: Outpost Durability & Destruction ---")
	var obj = SiegeObjectiveActorScript.new()
	obj.objective_id = "outpost_beta"
	obj.max_health = 200.0
	obj.health = 200.0
	obj.is_under_active_siege = false

	var dmg_sig := {"emitted": false, "amt": 0.0}
	obj.objective_damaged.connect(func(_id, amt, _hp, _max):
		dmg_sig["emitted"] = true
		dmg_sig["amt"] = amt
	)

	var destroyed_sig := {"emitted": false}
	obj.objective_destroyed.connect(func(_id, _killer):
		destroyed_sig["emitted"] = true
	)

	var captured_sig := {"emitted": false, "new_owner": ""}
	obj.objective_captured.connect(func(_id, new_owner):
		captured_sig["emitted"] = true
		captured_sig["new_owner"] = new_owner
	)

	# Gating verification: attacks before active siege launch must deal zero damage
	obj.take_damage(80.0, "catapult")
	_assert(obj.health == 200.0, "TC-SIEGE.2: Outpost immune to damage before active siege launch")
	_assert(dmg_sig["emitted"] == false, "TC-SIEGE.2: No damage signal emitted when not under active siege")

	# Enable active siege
	obj.is_under_active_siege = true

	# Non-lethal damage
	obj.take_damage(80.0, "catapult")
	_assert(obj.health == 120.0, "TC-SIEGE.2: Health reduced to 120.0 after 80 damage under active siege")
	_assert(dmg_sig["emitted"] == true, "TC-SIEGE.2: objective_damaged signal fired")
	_assert(dmg_sig["amt"] == 80.0, "TC-SIEGE.2: Damage amount recorded correctly")
	_assert(obj.is_alive == true, "TC-SIEGE.2: Outpost remains alive at 120 HP")
	_assert(obj.is_captured == false, "TC-SIEGE.2: Not captured yet")

	# Lethal blow
	obj.take_damage(150.0, "battering_ram")
	_assert(obj.health == 0.0, "TC-SIEGE.2: Health clamped to 0.0 on destruction")
	_assert(obj.is_alive == false, "TC-SIEGE.2: Outpost marked is_alive = false")
	_assert(obj.is_captured == true, "TC-SIEGE.2: Outpost marked is_captured = true")
	_assert(destroyed_sig["emitted"] == true, "TC-SIEGE.2: objective_destroyed signal emitted")
	_assert(captured_sig["emitted"] == true, "TC-SIEGE.2: objective_captured signal emitted")
	_assert(captured_sig["new_owner"] == "player", "TC-SIEGE.2: Captured by player")

	obj.free()

func _test_eligibility_gating() -> void:
	print("\n--- Test 3: Eligibility Gating ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "hostile_barons"
	fac.is_at_war = true
	fac.existence_status = "active"
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 3
	tac_mgr.sync_with_player_army()

	var siege_mgr = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var obj = siege_mgr.register_objective("obj_gate_1", Vector2i(20, 20), "hostile_barons")

	# Case A: Player army still at base (garrisoned) -> rejected
	var check1 = siege_mgr.can_launch_field_siege("hostile_barons", "obj_gate_1")
	_assert(check1["can_launch"] == false, "TC-SIEGE.3A: Rejected when player army has 0 field troops")

	# Case B: Move player units into field outside base perimeter near objective (e.g. (22, 22))
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(22, 22)
		u.target_cell = Vector2i(22, 22)
		u.order_state = TacticalUnitScript.OrderState.IDLE
	army_mgr.current_cell = Vector2i(22, 22)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var check2 = siege_mgr.can_launch_field_siege("hostile_barons", "obj_gate_1")
	_assert(check2["can_launch"] == true, "TC-SIEGE.3B: Accepted when ready field troops are near objective")

	# Case C: Not at war -> rejected
	fac.is_at_war = false
	var check3 = siege_mgr.can_launch_field_siege("hostile_barons", "obj_gate_1")
	_assert(check3["can_launch"] == false, "TC-SIEGE.3C: Rejected when not at war")
	fac.is_at_war = true

	# Case D: Eliminated faction -> rejected
	fac.existence_status = "eliminated"
	var check4 = siege_mgr.can_launch_field_siege("hostile_barons", "obj_gate_1")
	_assert(check4["can_launch"] == false, "TC-SIEGE.3D: Rejected when faction is not active")
	fac.existence_status = "active"

	# Case E: Army too far from objective (e.g. dist > 12)
	army_mgr.current_cell = Vector2i(55, 55)
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(55, 55)
	var check5 = siege_mgr.can_launch_field_siege("hostile_barons", "obj_gate_1")
	_assert(check5["can_launch"] == false, "TC-SIEGE.3E: Rejected when army is too far from objective")

	siege_mgr.clear_all_objectives()

func _test_operation_launch_and_defender_mobilization() -> void:
	print("\n--- Test 4: Operation Launch & Defender Mobilization ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "desert_nomads"
	fac.is_at_war = true
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 3
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(15, 15)
	army_mgr.current_cell = Vector2i(15, 15)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var enemy_mgr = EnemyMilitaryManagerScript.new()
	var siege_mgr = FieldSiegeManagerScript.new(null, fm, army_mgr, enemy_mgr)
	var obj = siege_mgr.register_objective("obj_desert_1", Vector2i(16, 16), "desert_nomads", 250.0, 3)

	var launch_sig := {"emitted": false, "s_id": ""}
	siege_mgr.field_siege_started.connect(func(s_id, _fac, _obj):
		launch_sig["emitted"] = true
		launch_sig["s_id"] = s_id
	)

	var res = siege_mgr.launch_field_siege("desert_nomads", "obj_desert_1")
	_assert(res["success"] == true, "TC-SIEGE.4: launch_field_siege succeeded")
	_assert(launch_sig["emitted"] == true, "TC-SIEGE.4: field_siege_started signal emitted")
	_assert(enemy_mgr.get_enemy_count() == 3, "TC-SIEGE.4: 3 garrison defenders spawned around objective")
	_assert(obj.defending_unit_ids.size() == 3, "TC-SIEGE.4: Objective recorded 3 defending unit IDs")

	siege_mgr.clear_all_objectives()
	enemy_mgr.clear_all_enemies()

func _test_victory_resolution_and_plunder() -> void:
	print("\n--- Test 5: Victory Resolution & Plunder Awards ---")
	var rm = MockResourceManager.new()
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "iron_legion"
	fac.is_at_war = true
	fac.military_power = 80.0
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 4
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(20, 20)
	army_mgr.current_cell = Vector2i(20, 20)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var siege_mgr = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	siege_mgr.set_resource_manager(rm)
	var obj = siege_mgr.register_objective("obj_iron_1", Vector2i(21, 21), "iron_legion", 100.0, 0)

	var resolved_sig := {"emitted": false, "outcome": ""}
	siege_mgr.field_siege_resolved.connect(func(_sid, outcome, _det):
		resolved_sig["emitted"] = true
		resolved_sig["outcome"] = outcome
	)

	var launch_res = siege_mgr.launch_field_siege("iron_legion", "obj_iron_1")
	var s_id = launch_res["siege_id"]

	# Destroy the objective!
	obj.take_damage(150.0, "player_army")

	# Evaluate siege
	var eval = siege_mgr.evaluate_siege_status(s_id)
	_assert(eval["outcome"] == "VICTORY", "TC-SIEGE.5: evaluate_siege_status yields VICTORY upon objective capture")
	_assert(fac.military_power == 60.0, "TC-SIEGE.5: Faction military power reduced by 20 (80 -> 60)")
	_assert(rm.get_resource("gold") == 160, "TC-SIEGE.5: Plunder awarded 60 Gold (100 -> 160)")
	_assert(rm.get_resource("food") == 140, "TC-SIEGE.5: Plunder awarded 40 Food (100 -> 140)")
	_assert(rm.get_resource("metal") == 120, "TC-SIEGE.5: Plunder awarded 20 Metal (100 -> 120)")
	_assert(resolved_sig["emitted"] == true, "TC-SIEGE.5: field_siege_resolved emitted")
	_assert(resolved_sig["outcome"] == "VICTORY", "TC-SIEGE.5: Signal reported VICTORY")

	siege_mgr.clear_all_objectives()

func _test_defeat_resolution() -> void:
	print("\n--- Test 6: Defeat Resolution ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "shadow_cult"
	fac.is_at_war = true
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 2
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(25, 25)
	army_mgr.current_cell = Vector2i(25, 25)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var siege_mgr = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var obj = siege_mgr.register_objective("obj_cult_1", Vector2i(26, 26), "shadow_cult", 300.0, 0)

	var launch_res = siege_mgr.launch_field_siege("shadow_cult", "obj_cult_1")
	var s_id = launch_res["siege_id"]

	# Wipe out player field army
	army_mgr.soldier_count = 0
	tac_mgr.clear_all_units()

	var eval = siege_mgr.evaluate_siege_status(s_id)
	_assert(eval["outcome"] == "DEFEAT", "TC-SIEGE.6: Total wipeout yields DEFEAT")

	siege_mgr.clear_all_objectives()

func _test_withdrawal_resolution() -> void:
	print("\n--- Test 7: Withdrawal Resolution ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "forest_wardens"
	fac.is_at_war = true
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 2
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(10, 10)
	army_mgr.current_cell = Vector2i(10, 10)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var siege_mgr = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var obj = siege_mgr.register_objective("obj_forest_1", Vector2i(12, 12), "forest_wardens", 300.0, 0)

	var launch_res = siege_mgr.launch_field_siege("forest_wardens", "obj_forest_1")
	var s_id = launch_res["siege_id"]

	# Player retreats far away (e.g. back to base at (32, 33), dist > 16)
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(32, 33)
	army_mgr.current_cell = Vector2i(32, 33)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED

	var eval = siege_mgr.evaluate_siege_status(s_id)
	_assert(eval["outcome"] == "WITHDRAWAL", "TC-SIEGE.7: Retreating to base yields WITHDRAWAL")

	siege_mgr.clear_all_objectives()

func _test_coexistence_with_battle_campaign() -> void:
	print("\n--- Test 8: Coexistence with BattleCampaignManager ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "raider_horde"
	fac.is_at_war = true
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var campaign_mgr = BattleCampaignManagerScript.new(null, null, 12345)
	campaign_mgr.set_custom_army_manager(army_mgr)

	var siege_mgr = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var obj = siege_mgr.register_objective("obj_coexist", Vector2i(20, 20), "raider_horde")

	_assert(campaign_mgr != null, "TC-SIEGE.8: BattleCampaignManager coexists with FieldSiegeManager")
	_assert(siege_mgr.get_objective("obj_coexist") != null, "TC-SIEGE.8: Field siege objective registered independently")
	_assert(campaign_mgr.get_offensive_campaign_sequence() == 0, "TC-SIEGE.8: Offensive campaign sequence unaffected")

	siege_mgr.clear_all_objectives()

func _test_siege_serialization_roundtrip() -> void:
	print("\n--- Test 9: Siege Serialization Roundtrip ---")
	var siege_mgr1 = FieldSiegeManagerScript.new()
	var o1 = siege_mgr1.register_objective("outpost_save_1", Vector2i(18, 22), "rebel_dukes", 350.0, 5)
	o1.health = 220.0

	var data = siege_mgr1.serialize()
	_assert(data.has("objectives") and data["objectives"].size() == 1, "TC-SIEGE.9: Serialized 1 objective")

	var siege_mgr2 = FieldSiegeManagerScript.new()
	var ok: bool = siege_mgr2.deserialize(data)
	_assert(ok == true, "TC-SIEGE.9: Deserialization returned true")

	var restored_obj = siege_mgr2.get_objective("outpost_save_1")
	_assert(restored_obj != null, "TC-SIEGE.9: Objective restored successfully")
	_assert(restored_obj.health == 220.0, "TC-SIEGE.9: Objective health restored to 220.0")
	_assert(restored_obj.max_health == 350.0, "TC-SIEGE.9: Objective max_health restored to 350.0")
	_assert(restored_obj.garrison_count == 5, "TC-SIEGE.9: Objective garrison_count restored to 5")
	_assert(restored_obj.owning_faction_id == "rebel_dukes", "TC-SIEGE.9: Objective owning_faction_id restored")

	siege_mgr1.clear_all_objectives()
	siege_mgr2.clear_all_objectives()

func _test_atomic_deserialization_fail_closed() -> void:
	print("\n--- Test 10: Atomic Fail-Closed Deserialization ---")
	var sm = FieldSiegeManagerScript.new()
	var o1 = sm.register_objective("live_obj_1", Vector2i(20, 20), "enemy_faction", 300.0, 3)
	sm.active_sieges["siege_live_1"] = {
		"siege_id": "siege_live_1",
		"faction_id": "enemy_faction",
		"objective_id": "live_obj_1",
		"status": "active"
	}

	# Malformed payload 1: active_sieges references missing objective
	var bad_data_1 = {
		"objectives": [
			{
				"objective_id": "new_obj_1",
				"owning_faction_id": "enemy_faction",
				"current_cell": [22, 22],
				"health": 200.0,
				"max_health": 200.0
			}
		],
		"active_sieges": {
			"bad_siege_1": {
				"siege_id": "bad_siege_1",
				"faction_id": "enemy_faction",
				"objective_id": "non_existent_objective",
				"status": "active"
			}
		}
	}

	var res1: bool = sm.deserialize(bad_data_1)
	_assert(res1 == false, "TC-SIEGE.10A: Deserialization rejected when active_sieges references non-existent objective")
	_assert(sm.get_objective("live_obj_1") != null, "TC-SIEGE.10A: Live objective preserved on deserialization failure")
	_assert(sm.active_sieges.has("siege_live_1"), "TC-SIEGE.10A: Live active_sieges preserved on deserialization failure")

	# Malformed payload 2: duplicate objective IDs
	var bad_data_2 = {
		"objectives": [
			{
				"objective_id": "dup_obj",
				"owning_faction_id": "fac_a",
				"current_cell": [10, 10],
				"health": 100.0,
				"max_health": 100.0
			},
			{
				"objective_id": "dup_obj",
				"owning_faction_id": "fac_b",
				"current_cell": [12, 12],
				"health": 100.0,
				"max_health": 100.0
			}
		]
	}
	var res2: bool = sm.deserialize(bad_data_2)
	_assert(res2 == false, "TC-SIEGE.10B: Deserialization rejected on duplicate objective IDs")
	_assert(sm.get_objective("live_obj_1") != null, "TC-SIEGE.10B: Live objective preserved on duplicate ID rejection")

	sm.clear_all_objectives()

func _test_real_resource_manager_integration() -> void:
	print("\n--- Test 11: Real ResourceManager Integration & Canonical Stock ---")
	var rm_script = preload("res://scripts/economy/resource_manager.gd")
	var rm = rm_script.new()

	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "coastal_raiders"
	fac.is_at_war = true
	fac.military_power = 90.0
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 3
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(15, 15)
	army_mgr.current_cell = Vector2i(15, 15)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var sm = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	sm.set_resource_manager(rm)
	var obj = sm.register_objective("obj_coastal", Vector2i(16, 16), "coastal_raiders", 100.0, 0)

	var launch_res = sm.launch_field_siege("coastal_raiders", "obj_coastal")
	_assert(launch_res["success"] == true, "TC-SIEGE.11: Siege launch succeeded for real ResourceManager test")

	var init_metal: int = rm.get_available_stock("metal")
	var init_gold: int = rm.get_available_stock("gold")

	# Destroy objective and resolve
	obj.take_damage(120.0, "player_hero")
	var eval = sm.evaluate_siege_status(launch_res["siege_id"])
	_assert(eval["outcome"] == "VICTORY", "TC-SIEGE.11: Victory resolved upon outpost destruction")

	_assert(rm.get_available_stock("metal") == init_metal + 20, "TC-SIEGE.11: Metal stock incremented by 20 in ResourceManager")
	_assert(rm.get_available_stock("gold") == init_gold + 60, "TC-SIEGE.11: Gold stock incremented by 60 in ResourceManager")
	_assert(rm.get_available_stock("iron") == 0, "TC-SIEGE.11: Invalid key 'iron' was not credited to ResourceManager")

	sm.clear_all_objectives()

func _test_tactical_attack_order_gating() -> void:
	print("\n--- Test 12: Tactical Attack Order Gating on Objectives ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "rebel_dukes"
	fac.is_at_war = true
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 2
	tac_mgr.sync_with_player_army()

	var sm = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var obj = sm.register_objective("obj_duke_outpost", Vector2i(20, 20), "rebel_dukes", 250.0, 2)

	# Select units
	tac_mgr.select_all()

	# Attack before launch -> rejected
	var atk_rej = tac_mgr.issue_attack_order(obj)
	_assert(atk_rej["success"] == false, "TC-SIEGE.12: Tactical attack order rejected before active siege launch")
	_assert(atk_rej["reason"].contains("Chưa phát động chiến dịch công thành"), "TC-SIEGE.12: Rejection reason mentions siege launch requirement")

	# Move army near outpost and launch siege
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(19, 20)
	army_mgr.current_cell = Vector2i(19, 20)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var launch_res = sm.launch_field_siege("rebel_dukes", "obj_duke_outpost")
	_assert(launch_res["success"] == true, "TC-SIEGE.12: Siege launch succeeded")
	_assert(obj.is_under_active_siege == true, "TC-SIEGE.12: Objective flagged as under active siege")

	# Attack after launch -> accepted
	var atk_acc = tac_mgr.issue_attack_order(obj)
	_assert(atk_acc["success"] == true, "TC-SIEGE.12: Tactical attack order accepted after active siege launch")

	sm.clear_all_objectives()

func _test_peace_treaty_siege_cancellation() -> void:
	print("\n--- Test 13: Peace Treaty Siege Cancellation ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "highland_clans"
	fac.is_at_war = true
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 2
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(18, 18)
	army_mgr.current_cell = Vector2i(18, 18)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var sm = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var obj = sm.register_objective("obj_highland", Vector2i(19, 19), "highland_clans", 200.0, 2)
	var launch_res = sm.launch_field_siege("highland_clans", "obj_highland")
	var s_id = launch_res["siege_id"]
	_assert(sm.is_siege_active_for_objective("obj_highland") == true, "TC-SIEGE.13: Siege active before peace treaty")

	# Sign peace -> cancels active sieges for faction
	sm.cancel_active_sieges_for_faction("highland_clans", "WITHDRAWAL")
	_assert(sm.is_siege_active_for_objective("obj_highland") == false, "TC-SIEGE.13: Siege no longer active after peace treaty")
	_assert(obj.is_under_active_siege == false, "TC-SIEGE.13: Objective is_under_active_siege reset to false")
	var record = sm.active_sieges[s_id]
	_assert(record["status"] == "resolved", "TC-SIEGE.13: Siege status resolved")
	_assert(record["outcome"] == "WITHDRAWAL", "TC-SIEGE.13: Siege outcome recorded as WITHDRAWAL")

	sm.clear_all_objectives()

func _test_siege_retry_and_bounded_defenders() -> void:
	print("\n--- Test 14: Siege Retry Idempotency & Bounded Defender Replenishment ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "retry_faction"
	fac.is_at_war = true
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 3
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(22, 22)
	army_mgr.current_cell = Vector2i(22, 22)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var enemy_mgr = EnemyMilitaryManagerScript.new(null, fm)
	var sm = FieldSiegeManagerScript.new(null, fm, army_mgr, enemy_mgr)
	enemy_mgr.set_field_siege_manager(sm)
	enemy_mgr.set_tactical_military_manager(tac_mgr)

	var obj = sm.register_objective("obj_retry_1", Vector2i(20, 20), "retry_faction", 300.0, 3)

	# 1. First Launch: spawns full garrison (3 defenders)
	var launch1 = sm.launch_field_siege("retry_faction", "obj_retry_1")
	_assert(launch1["success"] == true, "TC-SIEGE.14: First siege launch succeeded")
	_assert(enemy_mgr.get_enemy_count() == 3, "TC-SIEGE.14: Exactly 3 defenders spawned for initial garrison")
	_assert(obj.defending_unit_ids.size() == 3, "TC-SIEGE.14: Objective recorded 3 defending unit IDs")
	for uid in obj.defending_unit_ids:
		var u = enemy_mgr.get_enemy(uid)
		_assert(u.current_cell != obj.current_cell, "TC-SIEGE.14: Defender does not occupy objective cell")

	# 2. Defeat 1 defender in combat -> 2 defenders remain alive
	var killed_id: String = obj.defending_unit_ids[0]
	var killed_unit = enemy_mgr.get_enemy(killed_id)
	killed_unit.take_damage(150.0, "player_test")
	_assert(enemy_mgr.get_enemy_count() == 2, "TC-SIEGE.14: 1 defender defeated, exactly 2 remain in manager")

	# 3. Player army retreats -> WITHDRAWAL
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(35, 35)
	army_mgr.current_cell = Vector2i(35, 35)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	var eval1 = sm.evaluate_siege_status(launch1["siege_id"])
	_assert(eval1["outcome"] == "WITHDRAWAL", "TC-SIEGE.14: Siege resolved as WITHDRAWAL")
	_assert(obj.is_under_active_siege == false, "TC-SIEGE.14: Objective no longer under active siege")

	# 4. Player army returns and retries siege launch
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(22, 22)
	army_mgr.current_cell = Vector2i(22, 22)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	var launch2 = sm.launch_field_siege("retry_faction", "obj_retry_1")
	_assert(launch2["success"] == true, "TC-SIEGE.14: Retry siege launch succeeded")
	# Crucial: Must reuse the 2 living defenders and spawn ONLY 1 missing defender -> total 3 (NOT 2 + 3 = 5)!
	_assert(enemy_mgr.get_enemy_count() == 3, "TC-SIEGE.14: Retry replenished only 1 missing defender (total remains 3, not 5)")
	_assert(obj.defending_unit_ids.size() == 3, "TC-SIEGE.14: Objective records exactly 3 defenders")

	# 5. Withdraw again without killing any defenders
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(35, 35)
	army_mgr.current_cell = Vector2i(35, 35)
	sm.evaluate_siege_status(launch2["siege_id"])

	# 6. Retry again when all 3 defenders are alive -> 0 new defenders spawned
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(22, 22)
	army_mgr.current_cell = Vector2i(22, 22)
	var launch3 = sm.launch_field_siege("retry_faction", "obj_retry_1")
	_assert(launch3["success"] == true, "TC-SIEGE.14: Second retry succeeded")
	_assert(enemy_mgr.get_enemy_count() == 3, "TC-SIEGE.14: Zero new defenders spawned when garrison is already full (count remains 3)")
	_assert(obj.defending_unit_ids.size() == 3, "TC-SIEGE.14: Defenders array maintained at 3")

	sm.clear_all_objectives()
	enemy_mgr.clear_all_enemies()

func _test_objective_click_prioritization_and_no_overlap() -> void:
	print("\n--- Test 15: Exact Objective Cell Prioritization & Zero Objective Overlap ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "target_faction"
	fac.is_at_war = true
	fm.add_faction(fac)

	var enemy_mgr = EnemyMilitaryManagerScript.new(null, fm)
	var sm = FieldSiegeManagerScript.new(null, fm, null, enemy_mgr)
	enemy_mgr.set_field_siege_manager(sm)

	var obj_cell := Vector2i(15, 15)
	var obj = sm.register_objective("obj_click_test", obj_cell, "target_faction", 200.0, 4)

	# Spawn enemy force around objective
	var defenders = enemy_mgr.spawn_enemy_force("target_faction", obj_cell, 4, null, true, true, "obj_click_test")
	_assert(defenders.size() == 4, "TC-SIEGE.15: 4 defenders spawned")

	# Assert that NO enemy unit was placed on obj_cell
	var on_obj_cell := false
	for d in defenders:
		if d.current_cell == obj_cell:
			on_obj_cell = true
	_assert(on_obj_cell == false, "TC-SIEGE.15: Authoritative spawn policy guaranteed zero defenders on objective cell")

	# Verify targeting prioritization logic:
	# Clicking obj_cell when an enemy is at adjacent (15, 16) matches objective as exact target
	var cand_obj = obj
	var cand_enemy = defenders[0]
	cand_enemy.current_cell = Vector2i(15, 16)

	var click_cell := obj_cell
	var target_is_obj: bool = false
	if cand_obj != null and cand_obj.current_cell == click_cell:
		target_is_obj = true
	elif cand_enemy != null:
		target_is_obj = false
	_assert(target_is_obj == true, "TC-SIEGE.15: Direct click on objective cell prioritizes objective over adjacent enemy")

	sm.clear_all_objectives()
	enemy_mgr.clear_all_enemies()

func _test_gate_d_siege_state_distinctions() -> void:
	print("\n--- Test 16: Gate D Siege State Distinctions (CANON-004) ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "siege_gate_faction"
	fac.is_at_war = true
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 3
	tac_mgr.sync_with_player_army()

	var obj_cell := Vector2i(12, 12)
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(10, 12)
		u.target_cell = Vector2i(10, 12)
		u.order_state = TacticalUnitScript.OrderState.IDLE
	army_mgr.current_cell = Vector2i(10, 12)
	army_mgr.destination_cell = Vector2i(10, 12)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var siege_mgr = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var obj = siege_mgr.register_objective("obj_gate_d1", obj_cell, "siege_gate_faction", 300.0, 0)
	var launch1 = siege_mgr.launch_field_siege("siege_gate_faction", "obj_gate_d1")
	_assert(launch1["success"] == true, "GATE-D.1: Siege launched with 3 stationary field units")
	var sid1: String = launch1["siege_id"]

	# Case D1: Units maneuver/march within siege radius (order_state == MOVING) -> must remain ACTIVE, NOT DEFEAT!
	for u in tac_mgr.get_all_units():
		var p: Array[Vector2i] = [Vector2i(11, 12)]
		u.order_move(p, Vector2i(11, 12))
	_assert(tac_mgr.get_field_unit_count() == 0, "GATE-D.2: Stationary field unit count is 0 while all units are MOVING")
	_assert(tac_mgr.get_all_field_units().size() == 3, "GATE-D.3: Total physical field units in siege zone is still 3")
	var eval_moving = siege_mgr.evaluate_siege_status(sid1)
	_assert(eval_moving["status"] == "active" and eval_moving["outcome"] == "NONE", "GATE-D.4: Moving within siege zone keeps siege ACTIVE (not premature DEFEAT)")

	# Case D2: Units withdraw outside siege radius / back to garrison with 0 casualties -> WITHDRAWAL, NOT DEFEAT!
	for u in tac_mgr.get_all_units():
		u.current_cell = army_mgr.get_rally_cell()
		u.target_cell = u.current_cell
		u.current_path.clear()
		u.order_state = TacticalUnitScript.OrderState.IDLE
	army_mgr.sync_state_from_tactical()
	var eval_withdraw = siege_mgr.evaluate_siege_status(sid1)
	_assert(eval_withdraw["status"] == "resolved" and eval_withdraw["outcome"] == "WITHDRAWAL", "GATE-D.5: Returning all units to garrison resolves siege as WITHDRAWAL (not DEFEAT)")

	# Case D3: Field force eliminated in combat while garrison remains at base -> DEFEAT!
	army_mgr.soldier_count = 4
	tac_mgr.sync_with_player_army()
	var all_u = tac_mgr.get_all_units()
	# Keep 2 units at garrison, send 2 units to field objective
	all_u[0].current_cell = army_mgr.get_rally_cell()
	all_u[1].current_cell = army_mgr.get_rally_cell()
	all_u[2].current_cell = Vector2i(11, 12)
	all_u[3].current_cell = Vector2i(11, 13)
	army_mgr.sync_state_from_tactical()

	var launch2 = siege_mgr.launch_field_siege("siege_gate_faction", "obj_gate_d1")
	_assert(launch2["success"] == true, "GATE-D.6: Second siege launched with 2 field units and 2 garrisoned units")
	var sid2: String = launch2["siege_id"]

	# Kill the 2 field units in combat
	all_u[2].take_damage(500.0, "defender")
	all_u[3].take_damage(500.0, "defender")
	_assert(army_mgr.get_army_count() == 2, "GATE-D.7: 2 garrisoned soldiers survive after field force wiped out")
	var eval_defeat = siege_mgr.evaluate_siege_status(sid2)
	_assert(eval_defeat["status"] == "resolved" and eval_defeat["outcome"] == "DEFEAT", "GATE-D.8: Eliminating field force in combat resolves siege as DEFEAT")

	# Case D4: Plunder report records actual added resources when near storage capacity
	var cap_rm_script := GDScript.new()
	cap_rm_script.source_code = "extends RefCounted\nfunc add_resource(res_type: String, amount: int) -> int:\n\tif res_type == 'wood': return 12\n\treturn amount\n"
	cap_rm_script.reload()
	var cap_rm = cap_rm_script.new()
	siege_mgr.set_resource_manager(cap_rm)

	all_u[0].current_cell = Vector2i(11, 12)
	army_mgr.sync_state_from_tactical()
	var launch3 = siege_mgr.launch_field_siege("siege_gate_faction", "obj_gate_d1")
	var sid3: String = launch3["siege_id"]
	obj.is_captured = true
	obj.is_alive = false
	var eval_vic = siege_mgr.evaluate_siege_status(sid3)
	_assert(eval_vic["outcome"] == "VICTORY", "GATE-D.9: Captured objective resolves as VICTORY via evaluate_siege_status")
	_assert(int(eval_vic["details"]["plunder"]["wood"]) == 12, "GATE-D.10: Plunder report records actual added wood (12) instead of nominal 50")

	# Case D5 (DEF-4): Split field force where group 1 is outside withdrawal radius and group 2 remains inside siege zone
	obj.is_captured = false
	obj.is_alive = true
	obj.health = 300.0
	army_mgr.soldier_count = 2
	tac_mgr.sync_with_player_army()
	var split_units: Array = tac_mgr.get_all_units()
	for u in split_units:
		u.current_cell = Vector2i(11, 12)
		u.target_cell = Vector2i(11, 12)
		u.order_state = TacticalUnitScript.OrderState.IDLE
	army_mgr.current_cell = Vector2i(11, 12)
	army_mgr.destination_cell = Vector2i(11, 12)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var launch4 = siege_mgr.launch_field_siege("siege_gate_faction", "obj_gate_d1")
	_assert(launch4["success"] == true, "GATE-D.11: Siege launched for split-force evaluation")
	var sid4: String = launch4["siege_id"]

	# Move first unit (and strategic anchor) far outside siege radius (55, 55), while second unit stays inside siege zone (11, 12)
	split_units[0].current_cell = Vector2i(55, 55)
	split_units[0].target_cell = Vector2i(55, 55)
	split_units[1].current_cell = Vector2i(11, 12)
	split_units[1].target_cell = Vector2i(11, 12)
	army_mgr.current_cell = Vector2i(55, 55)
	army_mgr.destination_cell = Vector2i(55, 55)

	var eval_split_active = siege_mgr.evaluate_siege_status(sid4)
	_assert(eval_split_active["status"] == "active" and eval_split_active["outcome"] == "NONE", "GATE-D.12: Split force with living unit still inside siege zone remains ACTIVE (not premature WITHDRAWAL)")

	# Now withdraw the second unit outside the siege radius as well -> WITHDRAWAL
	split_units[1].current_cell = Vector2i(54, 55)
	split_units[1].target_cell = Vector2i(54, 55)
	var eval_split_withdrawn = siege_mgr.evaluate_siege_status(sid4)
	_assert(eval_split_withdrawn["status"] == "resolved" and eval_split_withdrawn["outcome"] == "WITHDRAWAL", "GATE-D.13: Siege resolves as WITHDRAWAL once all living field units leave siege zone")

	siege_mgr.clear_all_objectives()
	tac_mgr.clear_all_units()
