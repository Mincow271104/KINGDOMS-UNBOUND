extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 2J: Army Equipment Progression & Combat Integration
## Covers TC-EQ.01 through TC-EQ.27:
## Progression & Economy:
##   TC-EQ.01: Baseline initialization (Tier 1, 1.00x multiplier, name 'Trang bị cơ bản')
##   TC-EQ.02: Upgrade Tier 1 -> Tier 2 (cost 30 Wood, 15 Metal -> 1.25x multiplier, name 'Trang bị rèn', signal emitted)
##   TC-EQ.03: Upgrade Tier 2 -> Tier 3 (cost 60 Wood, 30 Metal -> 1.50x multiplier, name 'Trang bị tinh luyện', signal emitted)
##   TC-EQ.04: Reject upgrade beyond Tier 3 fail-closed (0 cost deducted)
##   TC-EQ.05: Reject skipping tier (Tier 1 -> Tier 3 directly rejected)
##   TC-EQ.06: Reject upgrade when soldier_count == 0
##   TC-EQ.07: Reject upgrade when active barracks count == 0
##   TC-EQ.08: Reject upgrade when army movement_state == MARCHING or current_path not empty
##   TC-EQ.09: Reject upgrade when army movement_state == IDLE_AT_FIELD or current_cell != rally_cell
##   TC-EQ.10: Reject upgrade when insufficient Metal or Wood (atomic, 0 deduction)
##   TC-EQ.11: Atomic transaction rollback on reservation failure
##   TC-EQ.12: Preflight check can_upgrade_equipment is strictly read-only with 0 side effects
##   TC-EQ.13: New recruits inherit current army tier
##   TC-EQ.22: Re-entrancy guard against concurrent/nested upgrade calls during resource reservation
## Persistence & UI:
##   TC-EQ.18: Save/Load roundtrip preserves Tier 1, 2, 3 and restores identically
##   TC-EQ.19: SaveManager in-memory validation rejects invalid/corrupt equipment_tier fail-closed (2, 2.0, 2.5, "2", true, 0, 4, legacy)
##   TC-EQ.20: Legacy save lacking equipment_tier defaults smoothly to Tier 1
##   TC-EQ.21: HUD ArmyPanel displays tier standard, multiplier, and upgrade button state
##   TC-EQ.23: SaveManager disk-loading validation and integral float normalization (file roundtrip, 2.0, 2.5, "2", true, 0, 4, legacy)
## Combat Integration:
##   TC-EQ.14: BattleResolver offensive campaign reflects tier multiplier
##   TC-EQ.15: BattleResolver defensive raid reflects tier multiplier
##   TC-EQ.16: TacticalUnit effective damage scales by tier without mutating base attack_damage
##   TC-EQ.17: EnemyTacticalUnit does NOT inherit player tier multiplier
##   TC-EQ.24: TacticalUnit real attack loop damage application, cooldown, and attack_damage immutability
##   TC-EQ.25: BattleCampaignManager.launch_offensive_campaign() with PlayerArmyManager as source of truth (controlled seed)
##   TC-EQ.26: Defending raid resolution with mixed defense (recruited army + citizen guards) and settlement battle resolution
##   TC-EQ.27: Tactical strike against SiegeObjectiveActor durability at Tier 1 vs Tier 3

const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var passed_count: int = 0

class MockResourceManager:
	signal resource_changed(res_id: String, available: int, total: int)

	var stock: Dictionary = {}
	var reserved: Dictionary = {}
	var fail_reservation: bool = false
	var reserve_calls: int = 0
	var commit_calls: int = 0

	func _init(initial_stock: Dictionary = {}) -> void:
		stock = {
			EconomyConfigScript.RES_FOOD: 200,
			EconomyConfigScript.RES_WOOD: 200,
			EconomyConfigScript.RES_GOLD: 200,
			EconomyConfigScript.RES_STONE: 100,
			EconomyConfigScript.RES_METAL: 100
		}
		for k in initial_stock:
			stock[k] = initial_stock[k]
		reserved = {
			EconomyConfigScript.RES_FOOD: 0,
			EconomyConfigScript.RES_WOOD: 0,
			EconomyConfigScript.RES_GOLD: 0,
			EconomyConfigScript.RES_STONE: 0,
			EconomyConfigScript.RES_METAL: 0
		}

	func get_available_stock(res_id: String) -> int:
		return maxi(0, stock.get(res_id, 0) - reserved.get(res_id, 0))

	func can_afford(cost: Dictionary) -> bool:
		if fail_reservation:
			return false
		for res_id in cost:
			if get_available_stock(res_id) < cost[res_id]:
				return false
		return true

	func reserve_cost(cost: Dictionary) -> bool:
		reserve_calls += 1
		if not can_afford(cost):
			return false
		for res_id in cost:
			reserved[res_id] = reserved.get(res_id, 0) + cost[res_id]
			resource_changed.emit(res_id, get_available_stock(res_id), stock.get(res_id, 0))
		return true

	func commit_cost(cost: Dictionary) -> void:
		commit_calls += 1
		for res_id in cost:
			var amt: int = cost[res_id]
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - amt)
			stock[res_id] = maxi(0, stock.get(res_id, 0) - amt)
			resource_changed.emit(res_id, get_available_stock(res_id), stock.get(res_id, 0))

	func release_cost(cost: Dictionary) -> void:
		for res_id in cost:
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - cost[res_id])
			resource_changed.emit(res_id, get_available_stock(res_id), stock.get(res_id, 0))

	func consume_resource(res_id: String, amount: int) -> bool:
		var avail = get_available_stock(res_id)
		if avail >= amount:
			stock[res_id] = stock.get(res_id, 0) - amount
			return true
		return false

class MockEventManager:
	var events_logged: Array[String] = []
	func log_event(msg: String) -> void:
		events_logged.append(msg)

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2J ARMY EQUIPMENT TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  PACKAGE 2J ACCEPTANCE TESTS: ALL %d ASSERTIONS PASSED! (0 Failures)" % passed_count)
		else:
			printerr("  PACKAGE 2J ACCEPTANCE TESTS: %d FAILURE(S) ENCOUNTERED (%d Passed)" % [failures, passed_count])
		print("========================================================\n")
		quit(failures)
	return false

func _assert(condition: bool, test_name: String, error_msg: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		var extra := (" - " + error_msg) if not error_msg.is_empty() else ""
		printerr("  [FAIL] %s%s" % [test_name, extra])

func _write_temp_disk_save(path: String, army_tier_val: Variant, has_field: bool = true) -> bool:
	var army_dict: Dictionary = {"soldier_count": 5}
	if has_field:
		army_dict["equipment_tier"] = army_tier_val
	var save_data: Dictionary = {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"metadata": {"world_id": "test_tc_eq_23"},
		"resources": {},
		"buildings": [],
		"citizens": [],
		"player_army": army_dict
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(save_data))
	f.close()
	return true

func _create_test_world_data_with_barracks(active_count: int = 1) -> WorldGenerator.WorldData:
	var wd = WorldGeneratorScript.generate(12345)
	for i in range(active_count):
		var b: Dictionary = {
			"id": "barracks_%d" % i,
			"type": "barracks",
			"footprint": Vector2i(2, 2),
			"cell": Vector2i(30 + i * 3, 30),
			"state": "active",
			"max_workers": 0,
			"assigned_workers": []
		}
		wd.buildings.append(b)
	return wd

func _run_all_tests() -> void:
	# -------------------------------------------------------------------------
	# TC-EQ.01: Baseline initialization
	# -------------------------------------------------------------------------
	var army_mgr := PlayerArmyManagerScript.new()
	var mock_rm := MockResourceManager.new()
	var mock_em := MockEventManager.new()
	var wd := _create_test_world_data_with_barracks(1)
	army_mgr._custom_resource_mgr = mock_rm
	army_mgr._custom_world_data = wd
	army_mgr._custom_event_mgr = mock_em

	_assert(army_mgr.get_equipment_tier() == 1, "TC-EQ.01: Default equipment tier is 1")
	_assert(is_equal_approx(army_mgr.get_equipment_combat_multiplier(), 1.00), "TC-EQ.01: Default tier multiplier is 1.00x")
	_assert(army_mgr.get_equipment_tier_name() == "Trang bị cơ bản", "TC-EQ.01: Default tier name is 'Trang bị cơ bản'")
	_assert(army_mgr.get_equipment_upgrade_cost(1).is_empty(), "TC-EQ.01: Tier 1 upgrade cost is empty")

	# -------------------------------------------------------------------------
	# TC-EQ.06: Reject upgrade when soldier_count == 0
	# -------------------------------------------------------------------------
	var check_empty := army_mgr.can_upgrade_equipment(2)
	_assert(not check_empty.get("can_upgrade", false), "TC-EQ.06: Reject upgrade when soldier_count is 0")
	var up_empty_res := army_mgr.upgrade_equipment(2)
	_assert(not up_empty_res.get("success", false) and army_mgr.get_equipment_tier() == 1, "TC-EQ.06: upgrade_equipment returns false when army is empty")

	# Recruit 2 soldiers for subsequent tests
	var recruit_res := army_mgr.recruit(2)
	_assert(recruit_res.get("success", false) and army_mgr.get_army_count() == 2, "Setup: Recruited 2 soldiers")

	# -------------------------------------------------------------------------
	# TC-EQ.07: Reject upgrade when active barracks count == 0
	# -------------------------------------------------------------------------
	var no_barracks_wd := WorldGeneratorScript.generate(12345)
	var filtered: Array[Dictionary] = []
	for b in no_barracks_wd.buildings:
		if b.get("type") != "barracks":
			filtered.append(b)
	no_barracks_wd.buildings = filtered
	army_mgr._custom_world_data = no_barracks_wd
	var check_no_barracks := army_mgr.can_upgrade_equipment(2)
	_assert(not check_no_barracks.get("can_upgrade", false), "TC-EQ.07: Reject upgrade when no active barracks exist")
	army_mgr._custom_world_data = wd

	# -------------------------------------------------------------------------
	# TC-EQ.08: Reject upgrade when army movement_state == MARCHING or current_path not empty
	# -------------------------------------------------------------------------
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.MARCHING
	army_mgr.current_path = [Vector2i(32, 34)]
	var check_marching := army_mgr.can_upgrade_equipment(2)
	_assert(not check_marching.get("can_upgrade", false), "TC-EQ.08: Reject upgrade when army is MARCHING")
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	army_mgr.current_path.clear()

	# -------------------------------------------------------------------------
	# TC-EQ.09: Reject upgrade when army movement_state == IDLE_AT_FIELD or current_cell != rally_cell
	# -------------------------------------------------------------------------
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	army_mgr.current_cell = Vector2i(45, 45)
	var check_field := army_mgr.can_upgrade_equipment(2)
	_assert(not check_field.get("can_upgrade", false), "TC-EQ.09: Reject upgrade when army is IDLE_AT_FIELD away from rally")
	army_mgr.current_cell = army_mgr.rally_cell
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED

	# -------------------------------------------------------------------------
	# TC-EQ.05: Reject skipping tier (Tier 1 -> Tier 3 directly)
	# -------------------------------------------------------------------------
	var check_skip := army_mgr.can_upgrade_equipment(3)
	_assert(not check_skip.get("can_upgrade", false), "TC-EQ.05: Reject skipping directly to Tier 3 from Tier 1")

	# -------------------------------------------------------------------------
	# TC-EQ.10: Reject upgrade when insufficient Metal or Wood
	# -------------------------------------------------------------------------
	var poor_rm := MockResourceManager.new({
		EconomyConfigScript.RES_WOOD: 10, # Needs 30
		EconomyConfigScript.RES_METAL: 5   # Needs 15
	})
	army_mgr._custom_resource_mgr = poor_rm
	var check_poor := army_mgr.can_upgrade_equipment(2)
	_assert(not check_poor.get("can_upgrade", false), "TC-EQ.10: Reject upgrade when insufficient Wood and Metal")
	var up_poor_res := army_mgr.upgrade_equipment(2)
	_assert(not up_poor_res.get("success", false) and poor_rm.commit_calls == 0, "TC-EQ.10: 0 resources committed on failed upgrade")

	# -------------------------------------------------------------------------
	# TC-EQ.11: Atomic transaction rollback on reservation failure
	# -------------------------------------------------------------------------
	var rollback_rm := MockResourceManager.new({
		EconomyConfigScript.RES_WOOD: 50,
		EconomyConfigScript.RES_METAL: 50
	})
	rollback_rm.fail_reservation = true
	army_mgr._custom_resource_mgr = rollback_rm
	var up_rollback := army_mgr.upgrade_equipment(2)
	_assert(not up_rollback.get("success", false) and army_mgr.get_equipment_tier() == 1, "TC-EQ.11: Rollback leaves equipment at Tier 1 when reservation fails")

	# -------------------------------------------------------------------------
	# TC-EQ.12: Preflight check is strictly read-only
	# -------------------------------------------------------------------------
	army_mgr._custom_resource_mgr = mock_rm
	var wood_before: int = mock_rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var metal_before: int = mock_rm.get_available_stock(EconomyConfigScript.RES_METAL)
	var check_read_only := army_mgr.can_upgrade_equipment(2)
	_assert(check_read_only.get("can_upgrade", false), "TC-EQ.12: can_upgrade_equipment returns true when conditions met")
	_assert(mock_rm.get_available_stock(EconomyConfigScript.RES_WOOD) == wood_before and mock_rm.get_available_stock(EconomyConfigScript.RES_METAL) == metal_before, "TC-EQ.12: can_upgrade_equipment had 0 side effects on resources")
	_assert(army_mgr.get_equipment_tier() == 1, "TC-EQ.12: can_upgrade_equipment did not change equipment tier")

	# -------------------------------------------------------------------------
	# TC-EQ.02: Upgrade Tier 1 -> Tier 2
	# -------------------------------------------------------------------------
	var sig_data := {"tier": -1, "mult": -1.0}
	var signal_cb = func(new_tier: int, mult: float):
		sig_data["tier"] = new_tier
		sig_data["mult"] = mult
	army_mgr.equipment_tier_changed.connect(signal_cb)

	var up_t2 := army_mgr.upgrade_equipment(2)
	_assert(up_t2.get("success", false), "TC-EQ.02: Upgrade Tier 1 -> 2 succeeds")
	_assert(army_mgr.get_equipment_tier() == 2, "TC-EQ.02: Equipment tier is now 2")
	_assert(is_equal_approx(army_mgr.get_equipment_combat_multiplier(), 1.25), "TC-EQ.02: Tier 2 multiplier is 1.25x")
	_assert(army_mgr.get_equipment_tier_name() == "Trang bị rèn", "TC-EQ.02: Tier 2 name is 'Trang bị rèn'")
	_assert(sig_data["tier"] == 2 and is_equal_approx(sig_data["mult"], 1.25), "TC-EQ.02: equipment_tier_changed signal fired correctly")
	_assert(mock_rm.get_available_stock(EconomyConfigScript.RES_WOOD) == wood_before - 30, "TC-EQ.02: Deducted 30 Wood")
	_assert(mock_rm.get_available_stock(EconomyConfigScript.RES_METAL) == metal_before - 15, "TC-EQ.02: Deducted 15 Metal")

	# -------------------------------------------------------------------------
	# TC-EQ.03: Upgrade Tier 2 -> Tier 3
	# -------------------------------------------------------------------------
	var wood_before_t3: int = mock_rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var metal_before_t3: int = mock_rm.get_available_stock(EconomyConfigScript.RES_METAL)
	var up_t3 := army_mgr.upgrade_equipment(3)
	_assert(up_t3.get("success", false), "TC-EQ.03: Upgrade Tier 2 -> 3 succeeds")
	_assert(army_mgr.get_equipment_tier() == 3, "TC-EQ.03: Equipment tier is now 3")
	_assert(is_equal_approx(army_mgr.get_equipment_combat_multiplier(), 1.50), "TC-EQ.03: Tier 3 multiplier is 1.50x")
	_assert(army_mgr.get_equipment_tier_name() == "Trang bị tinh luyện", "TC-EQ.03: Tier 3 name is 'Trang bị tinh luyện'")
	_assert(sig_data["tier"] == 3 and is_equal_approx(sig_data["mult"], 1.50), "TC-EQ.03: equipment_tier_changed signal fired for Tier 3")
	_assert(mock_rm.get_available_stock(EconomyConfigScript.RES_WOOD) == wood_before_t3 - 60, "TC-EQ.03: Deducted 60 Wood")
	_assert(mock_rm.get_available_stock(EconomyConfigScript.RES_METAL) == metal_before_t3 - 30, "TC-EQ.03: Deducted 30 Metal")

	# -------------------------------------------------------------------------
	# TC-EQ.04: Reject upgrade beyond Tier 3 fail-closed
	# -------------------------------------------------------------------------
	var check_t4 := army_mgr.can_upgrade_equipment(4)
	_assert(not check_t4.get("can_upgrade", false), "TC-EQ.04: Reject upgrade beyond Tier 3 (can_upgrade is false)")
	var up_t4 := army_mgr.upgrade_equipment(4)
	_assert(not up_t4.get("success", false) and army_mgr.get_equipment_tier() == 3, "TC-EQ.04: upgrade_equipment beyond Tier 3 fails closed")

	# -------------------------------------------------------------------------
	# TC-EQ.13: New recruits inherit current army tier standard
	# -------------------------------------------------------------------------
	var recruit_t3 := army_mgr.recruit(1)
	_assert(recruit_t3.get("success", false) and army_mgr.get_army_count() == 3, "TC-EQ.13: Recruited new soldier")
	_assert(army_mgr.get_equipment_tier() == 3, "TC-EQ.13: Army maintains Tier 3 standard for new recruit")

	# -------------------------------------------------------------------------
	# TC-EQ.16: TacticalUnit effective damage scales by tier without mutating attack_damage
	# -------------------------------------------------------------------------
	var tac_unit := TacticalUnitScript.new()
	tac_unit.attack_damage = 25.0
	tac_unit.faction_id = "player"
	tac_unit.set_player_army_manager(army_mgr)

	_assert(is_equal_approx(tac_unit.get_equipment_multiplier(), 1.50), "TC-EQ.16: TacticalUnit multiplier matches army manager Tier 3 (1.50x)")
	_assert(is_equal_approx(tac_unit.get_effective_attack_damage(), 37.5), "TC-EQ.16: Effective damage is 25.0 * 1.50 = 37.5")
	_assert(is_equal_approx(tac_unit.attack_damage, 25.0), "TC-EQ.16: Base attack_damage is NOT mutated (remains 25.0)")

	# -------------------------------------------------------------------------
	# TC-EQ.17: EnemyTacticalUnit does NOT inherit player tier multiplier
	# -------------------------------------------------------------------------
	var enemy_unit := EnemyTacticalUnitScript.new()
	enemy_unit.attack_damage = 25.0
	enemy_unit.owning_faction_id = "enemy_faction"
	enemy_unit.faction_id = "enemy_faction"
	enemy_unit.set_player_army_manager(army_mgr)

	_assert(is_equal_approx(enemy_unit.get_equipment_multiplier(), 1.00), "TC-EQ.17: Enemy unit equipment multiplier is strictly 1.00x")
	_assert(is_equal_approx(enemy_unit.get_effective_attack_damage(), 25.0), "TC-EQ.17: Enemy unit effective damage remains 25.0")

	tac_unit.free()
	enemy_unit.free()

	# -------------------------------------------------------------------------
	# TC-EQ.14 & TC-EQ.15: BattleCampaignManager and BattleResolver integration
	# -------------------------------------------------------------------------
	var camp_mgr := BattleCampaignManagerScript.new()
	camp_mgr.set_player_army_manager(army_mgr)
	camp_mgr.set_custom_resource_manager(mock_rm)
	camp_mgr.set_custom_world_data(wd)

	var def_force: Dictionary = camp_mgr.construct_defending_force()
	_assert(def_force.get("equipment_tier") == 3, "TC-EQ.15: Defending force reflects player army equipment_tier 3")

	# Test BattleResolver equipment multiplier formula directly
	var atk_force_t1: Dictionary = {"troops": 10, "equipment_tier": 1, "morale": 70.0, "terrain_multiplier": 1.0}
	var atk_force_t3: Dictionary = {"troops": 10, "equipment_tier": 3, "morale": 70.0, "terrain_multiplier": 1.0}
	var test_def: Dictionary = {"troops": 10, "equipment_tier": 1, "morale": 70.0, "fortification_level": 0, "terrain_multiplier": 1.0, "resources": {}}

	var res_t1 = BattleResolverScript.resolve_battle(atk_force_t1, test_def, 42)
	var res_t3 = BattleResolverScript.resolve_battle(atk_force_t3, test_def, 42)
	# At Tier 3, attacker has 1.50x equipment bonus vs 1.00x, so defender should suffer higher casualties or attacker wins more decisively
	_assert(res_t3.defender_casualties >= res_t1.defender_casualties, "TC-EQ.14: Tier 3 equipment yields >= casualties on defender than Tier 1")

	# -------------------------------------------------------------------------
	# TC-EQ.18: Save/Load roundtrip preserves equipment_tier
	# -------------------------------------------------------------------------
	var serialized: Dictionary = army_mgr.serialize()
	_assert(serialized.has("equipment_tier") and serialized["equipment_tier"] == 3, "TC-EQ.18: serialize() includes equipment_tier 3")

	var fresh_army_mgr := PlayerArmyManagerScript.new()
	fresh_army_mgr.deserialize(serialized)
	_assert(fresh_army_mgr.get_equipment_tier() == 3, "TC-EQ.18: deserialize() restored equipment_tier 3")
	_assert(is_equal_approx(fresh_army_mgr.get_equipment_combat_multiplier(), 1.50), "TC-EQ.18: Restored army manager has 1.50x multiplier")

	# -------------------------------------------------------------------------
	# TC-EQ.19: SaveManager validation rejects invalid/corrupt equipment_tier fail-closed
	# Tests exact cases: 2, 2.0, 2.5, "2", true, 0, 4, and missing legacy field
	# -------------------------------------------------------------------------
	var base_save: Dictionary = {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"metadata": {"world_id": "test_world"},
		"resources": {},
		"buildings": [],
		"citizens": []
	}

	# 1. Valid strict int: 2
	var test_save_valid: Dictionary = base_save.duplicate(true)
	test_save_valid["player_army"] = {"soldier_count": 2, "equipment_tier": 2}
	var v_valid: Dictionary = SaveManagerScript.validate_save_data(test_save_valid)
	_assert(v_valid.get("valid", false), "TC-EQ.19: SaveManager accepts valid strict int equipment_tier (2)")

	# 2. Strict int enforcement: 2.0 (float rejected in memory validation)
	var test_save_float_integral: Dictionary = base_save.duplicate(true)
	test_save_float_integral["player_army"] = {"soldier_count": 2, "equipment_tier": 2.0}
	var v_float_int: Dictionary = SaveManagerScript.validate_save_data(test_save_float_integral)
	_assert(not v_float_int.get("valid", true), "TC-EQ.19: SaveManager strictly rejects float 2.0")

	# 3. Float with fractional part: 2.5
	var test_save_float: Dictionary = base_save.duplicate(true)
	test_save_float["player_army"] = {"soldier_count": 2, "equipment_tier": 2.5}
	var v_float: Dictionary = SaveManagerScript.validate_save_data(test_save_float)
	_assert(not v_float.get("valid", true), "TC-EQ.19: SaveManager rejects non-integer float 2.5")

	# 4. String representation: "2"
	var test_save_str: Dictionary = base_save.duplicate(true)
	test_save_str["player_army"] = {"soldier_count": 2, "equipment_tier": "2"}
	var v_str: Dictionary = SaveManagerScript.validate_save_data(test_save_str)
	_assert(not v_str.get("valid", true), "TC-EQ.19: SaveManager rejects string '2'")

	# 5. Boolean value: true
	var test_save_bool: Dictionary = base_save.duplicate(true)
	test_save_bool["player_army"] = {"soldier_count": 2, "equipment_tier": true}
	var v_bool: Dictionary = SaveManagerScript.validate_save_data(test_save_bool)
	_assert(not v_bool.get("valid", true), "TC-EQ.19: SaveManager rejects bool true")

	# 6. Lower out of bounds: 0
	var test_save_t0: Dictionary = base_save.duplicate(true)
	test_save_t0["player_army"] = {"soldier_count": 2, "equipment_tier": 0}
	var v_t0: Dictionary = SaveManagerScript.validate_save_data(test_save_t0)
	_assert(not v_t0.get("valid", true), "TC-EQ.19: SaveManager rejects equipment_tier 0 (< 1)")

	# 7. Upper out of bounds: 4
	var test_save_t4: Dictionary = base_save.duplicate(true)
	test_save_t4["player_army"] = {"soldier_count": 2, "equipment_tier": 4}
	var v_t4: Dictionary = SaveManagerScript.validate_save_data(test_save_t4)
	_assert(not v_t4.get("valid", true), "TC-EQ.19: SaveManager rejects equipment_tier 4 (> 3)")

	# 8. Missing legacy field
	var test_save_legacy: Dictionary = base_save.duplicate(true)
	test_save_legacy["player_army"] = {"soldier_count": 2}
	var v_legacy: Dictionary = SaveManagerScript.validate_save_data(test_save_legacy)
	_assert(v_legacy.get("valid", false), "TC-EQ.19: SaveManager accepts missing legacy field smoothly")

	# -------------------------------------------------------------------------
	# TC-EQ.20: Legacy save lacking equipment_tier defaults smoothly to Tier 1
	# -------------------------------------------------------------------------
	var legacy_army_data: Dictionary = {
		"soldier_count": 5,
		"is_supplied": true
	}
	var legacy_army_mgr := PlayerArmyManagerScript.new()
	legacy_army_mgr.deserialize(legacy_army_data)
	_assert(legacy_army_mgr.get_equipment_tier() == 1, "TC-EQ.20: Legacy save lacking equipment_tier defaults to Tier 1")
	_assert(is_equal_approx(legacy_army_mgr.get_equipment_combat_multiplier(), 1.00), "TC-EQ.20: Legacy save has 1.00x multiplier")

	# -------------------------------------------------------------------------
	# TC-EQ.21: HUD ArmyPanel displays tier standard, multiplier, and upgrade button state
	# -------------------------------------------------------------------------
	var hud = world_instance.get_node_or_null("HUD")
	if hud != null:
		hud.set_player_army_manager(army_mgr)
		hud._refresh_army_panel()
		var tier_label: Label = hud.get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ArmyStatsVBox/EquipmentTierLabel")
		var up_btn: Button = hud.get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/UpgradeEquipmentBtn")
		_assert(tier_label != null, "TC-EQ.21: EquipmentTierLabel present in HUD")
		_assert(up_btn != null, "TC-EQ.21: UpgradeEquipmentBtn present in HUD")
		if tier_label != null:
			_assert(tier_label.text.contains("Cấp 3") and tier_label.text.contains("1.50"), "TC-EQ.21: Tier label displays Cấp 3 and 1.50x")
		if up_btn != null:
			_assert(up_btn.disabled, "TC-EQ.21: Upgrade button disabled when already at max Tier 3")
	else:
		_assert(false, "TC-EQ.21: HUD node not found in world_instance")

	# -------------------------------------------------------------------------
	# TC-EQ.22: Safe synchronous transaction guard against re-entrancy (STAGE B)
	# Attaches a one-shot resource_changed listener that calls upgrade_equipment() during reservation.
	# With sufficient resources for 2 upgrades (Tier 1->2: 30W, 15M; Tier 2->3: 60W, 30M -> total 90W, 45M).
	# Stock: 150 Wood, 100 Metal.
	# -------------------------------------------------------------------------
	var reentrant_army_mgr := PlayerArmyManagerScript.new()
	reentrant_army_mgr.soldier_count = 5
	reentrant_army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	reentrant_army_mgr.current_cell = reentrant_army_mgr.rally_cell
	reentrant_army_mgr._custom_world_data = _create_test_world_data_with_barracks(1)

	var reentrant_rm := MockResourceManager.new({
		EconomyConfigScript.RES_WOOD: 150,
		EconomyConfigScript.RES_METAL: 100
	})
	reentrant_army_mgr._custom_resource_mgr = reentrant_rm

	var reentrant_signals: Array[Dictionary] = []
	reentrant_army_mgr.equipment_tier_changed.connect(func(t, m):
		reentrant_signals.append({"tier": t, "mult": m})
	)

	var nested_call_result: Dictionary = {}
	var reentrant_cb: Callable
	reentrant_cb = func(res_id: String, _avail: int, _total: int):
		if res_id == EconomyConfigScript.RES_WOOD and not nested_call_result.has("called"):
			nested_call_result["called"] = true
			# Attempt nested re-entrant upgrade during the first reservation
			nested_call_result["res"] = reentrant_army_mgr.upgrade_equipment()

	reentrant_rm.resource_changed.connect(reentrant_cb)

	# Execute primary upgrade Tier 1 -> Tier 2
	var primary_res := reentrant_army_mgr.upgrade_equipment()

	reentrant_rm.resource_changed.disconnect(reentrant_cb)

	# Assertions for TC-EQ.22
	_assert(primary_res.get("success", false), "TC-EQ.22: Primary upgrade succeeded")
	_assert(nested_call_result.get("called", false), "TC-EQ.22: Re-entrant listener was invoked during reservation")
	_assert(not nested_call_result.get("res", {}).get("success", true), "TC-EQ.22: Nested re-entrant upgrade was safely blocked fail-closed")
	_assert(nested_call_result.get("res", {}).get("reason", "").contains("đang được xử lý"), "TC-EQ.22: Nested upgrade failed with in-flight transaction reason")

	# Stock deduction verification: exactly 1 upgrade cost deducted (30 Wood, 15 Metal)
	# 150 - 30 = 120 Wood, 100 - 15 = 85 Metal
	_assert(reentrant_rm.stock[EconomyConfigScript.RES_WOOD] == 120 and reentrant_rm.stock[EconomyConfigScript.RES_METAL] == 85, "TC-EQ.22: Exactly one upgrade cost deducted (120W, 85M remaining)")

	# Equipment tier must be 2, NOT 3
	_assert(reentrant_army_mgr.get_equipment_tier() == 2, "TC-EQ.22: Equipment tier transitioned exactly once (Tier 2)")

	# Signal must be emitted exactly once
	_assert(reentrant_signals.size() == 1 and reentrant_signals[0]["tier"] == 2, "TC-EQ.22: Exactly one equipment_tier_changed signal emitted")

	# No stranded reserved resources
	_assert(reentrant_rm.reserved[EconomyConfigScript.RES_WOOD] == 0 and reentrant_rm.reserved[EconomyConfigScript.RES_METAL] == 0, "TC-EQ.22: Zero reserved resources stranded in stock")

	# Subsequent normal upgrade works when in-flight transaction is complete
	var subsequent_res := reentrant_army_mgr.upgrade_equipment(3)
	_assert(subsequent_res.get("success", false), "TC-EQ.22: Subsequent normal upgrade to Tier 3 succeeded")
	_assert(reentrant_army_mgr.get_equipment_tier() == 3, "TC-EQ.22: Equipment tier reached Tier 3 on subsequent upgrade")
	_assert(reentrant_rm.stock[EconomyConfigScript.RES_WOOD] == 60 and reentrant_rm.stock[EconomyConfigScript.RES_METAL] == 55, "TC-EQ.22: Additional 60W, 30M deducted for Tier 3 (60W, 55M remaining)")
	_assert(reentrant_signals.size() == 2 and reentrant_signals[1]["tier"] == 3, "TC-EQ.22: Second signal emitted for Tier 3")

	# -------------------------------------------------------------------------
	# TC-EQ.23: SaveManager disk-loading validation & JSON integral float normalization
	# Tests load_from_file() and _read_and_validate_save_file() with genuine disk JSON files:
	# 1. Valid on-disk Tier 1 loads and validates as int(1)
	# 2. Valid on-disk Tier 2 normalizes JSON float 2.0 to strict int(2)
	# 3. Valid on-disk Tier 3 normalizes JSON float 3.0 to strict int(3)
	# 4. Malformed on-disk fractional float 2.5 rejected fail-closed
	# 5. Malformed on-disk string "2" rejected fail-closed
	# 6. Malformed on-disk boolean true rejected fail-closed
	# 7. Out-of-bounds on-disk 0 rejected fail-closed
	# 8. Out-of-bounds on-disk 4 rejected fail-closed
	# 9. Legacy on-disk save lacking equipment_tier loads cleanly and defaults to Tier 1
	# -------------------------------------------------------------------------
	var tmp_disk_save_path := "user://saves/test_tc_eq_23_tmp.json"

	# 1. On-disk Tier 1
	_write_temp_disk_save(tmp_disk_save_path, 1)
	var disk_res_t1 := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(disk_res_t1.get("valid", false) and disk_res_t1.get("data", {}).get("player_army", {}).get("equipment_tier") == 1, "TC-EQ.23: On-disk Tier 1 loads and validates as int(1)")

	# 2. On-disk Tier 2 (integral float normalization from JSON)
	_write_temp_disk_save(tmp_disk_save_path, 2)
	var disk_res_t2 := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(disk_res_t2.get("valid", false) and disk_res_t2.get("data", {}).get("player_army", {}).get("equipment_tier") == 2, "TC-EQ.23: On-disk Tier 2 normalizes JSON float 2.0 to strict int(2)")

	# 3. On-disk Tier 3 (integral float normalization from JSON)
	_write_temp_disk_save(tmp_disk_save_path, 3)
	var disk_res_t3 := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(disk_res_t3.get("valid", false) and disk_res_t3.get("data", {}).get("player_army", {}).get("equipment_tier") == 3, "TC-EQ.23: On-disk Tier 3 normalizes JSON float 3.0 to strict int(3)")

	# 4. Malformed on-disk fractional value: 2.5
	_write_temp_disk_save(tmp_disk_save_path, 2.5)
	var disk_res_frac := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(not disk_res_frac.get("valid", true), "TC-EQ.23: On-disk fractional float 2.5 rejected fail-closed")

	# 5. Malformed on-disk string: "2"
	_write_temp_disk_save(tmp_disk_save_path, "2")
	var disk_res_str := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(not disk_res_str.get("valid", true), "TC-EQ.23: On-disk string '2' rejected fail-closed")

	# 6. Malformed on-disk boolean: true
	_write_temp_disk_save(tmp_disk_save_path, true)
	var disk_res_bool := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(not disk_res_bool.get("valid", true), "TC-EQ.23: On-disk boolean true rejected fail-closed")

	# 7. Out-of-bounds on-disk: 0
	_write_temp_disk_save(tmp_disk_save_path, 0)
	var disk_res_oob0 := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(not disk_res_oob0.get("valid", true), "TC-EQ.23: On-disk out-of-bounds 0 rejected fail-closed")

	# 8. Out-of-bounds on-disk: 4
	_write_temp_disk_save(tmp_disk_save_path, 4)
	var disk_res_oob4 := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(not disk_res_oob4.get("valid", true), "TC-EQ.23: On-disk out-of-bounds 4 rejected fail-closed")

	# 9. Legacy on-disk save lacking equipment_tier
	_write_temp_disk_save(tmp_disk_save_path, null, false)
	var disk_res_legacy := SaveManagerScript._read_and_validate_save_file(tmp_disk_save_path)
	_assert(disk_res_legacy.get("valid", false), "TC-EQ.23: On-disk legacy save without equipment_tier passes schema validation")
	_assert(not disk_res_legacy.get("data", {}).get("player_army", {}).has("equipment_tier"), "TC-EQ.23: On-disk legacy payload preserves missing field for runtime migration")

	# Clean up temporary test file
	if FileAccess.file_exists(tmp_disk_save_path):
		DirAccess.remove_absolute(tmp_disk_save_path)

	# -------------------------------------------------------------------------
	# TC-EQ.24: Real TacticalUnit attack loop execution (Tier 1 vs Tier 2 vs Tier 3)
	# Asserts real damage application via advance_combat(), cooldown, and base attack_damage immutability
	# -------------------------------------------------------------------------
	var combat_army_mgr := PlayerArmyManagerScript.new()
	combat_army_mgr.soldier_count = 5
	combat_army_mgr.equipment_tier = 1

	var player_combat_unit := TacticalUnitScript.new()
	player_combat_unit.unit_id = "test_player_soldier"
	player_combat_unit.faction_id = "player"
	player_combat_unit.attack_damage = 25.0
	player_combat_unit.current_cell = Vector2i(10, 10)
	player_combat_unit.set_player_army_manager(combat_army_mgr)
	world_instance.add_child(player_combat_unit)

	var target_enemy := EnemyTacticalUnitScript.new()
	target_enemy.unit_id = "test_enemy_soldier"
	target_enemy.faction_id = "hostile_factions"
	target_enemy.owning_faction_id = "hostile_factions"
	target_enemy.attack_damage = 25.0
	target_enemy.max_health = 200.0
	target_enemy.health = 200.0
	target_enemy.current_cell = Vector2i(10, 11) # adjacent Manhattan distance 1
	target_enemy.set_player_army_manager(combat_army_mgr)
	world_instance.add_child(target_enemy)

	# Tier 1 strike: 25.00 damage
	player_combat_unit.order_attack(target_enemy)
	player_combat_unit.attack_cooldown_remaining = 0.0
	var hp_before_t1 := target_enemy.health
	player_combat_unit.advance_combat(0.016, 1.0)
	var dmg_t1 := hp_before_t1 - target_enemy.health
	_assert(is_equal_approx(dmg_t1, 25.00), "TC-EQ.24: Tier 1 real combat strike dealt exactly 25.00 damage")
	_assert(is_equal_approx(player_combat_unit.attack_damage, 25.0), "TC-EQ.24: Base attack_damage is strictly 25.00 (immutable)")

	# Upgrade to Tier 2 and strike: 31.25 damage
	combat_army_mgr.equipment_tier = 2
	player_combat_unit.attack_cooldown_remaining = 0.0
	var hp_before_t2 := target_enemy.health
	player_combat_unit.advance_combat(0.016, 1.0)
	var dmg_t2 := hp_before_t2 - target_enemy.health
	_assert(is_equal_approx(dmg_t2, 31.25), "TC-EQ.24: Tier 2 real combat strike dealt exactly 31.25 damage (1.25x)")
	_assert(is_equal_approx(player_combat_unit.attack_damage, 25.0), "TC-EQ.24: Base attack_damage still strictly 25.00 after Tier 2 strike")

	# Upgrade to Tier 3 and strike: 37.50 damage
	combat_army_mgr.equipment_tier = 3
	player_combat_unit.attack_cooldown_remaining = 0.0
	var hp_before_t3 := target_enemy.health
	player_combat_unit.advance_combat(0.016, 1.0)
	var dmg_t3 := hp_before_t3 - target_enemy.health
	_assert(is_equal_approx(dmg_t3, 37.50), "TC-EQ.24: Tier 3 real combat strike dealt exactly 37.50 damage (1.50x)")
	_assert(is_equal_approx(player_combat_unit.attack_damage, 25.0), "TC-EQ.24: Base attack_damage still strictly 25.00 after Tier 3 strike")

	# Enemy unit strikes back: does NOT inherit player tier multiplier
	target_enemy.order_attack(player_combat_unit)
	target_enemy.attack_cooldown_remaining = 0.0
	var player_hp_before := player_combat_unit.health
	target_enemy.advance_combat(0.016, 1.0)
	var enemy_dmg := player_hp_before - player_combat_unit.health
	_assert(is_equal_approx(enemy_dmg, 25.00), "TC-EQ.24: Enemy strike deals 25.00 damage without player multiplier")

	player_combat_unit.queue_free()
	target_enemy.queue_free()

	# -------------------------------------------------------------------------
	# TC-EQ.25: Offensive Campaign through BattleCampaignManager with PlayerArmyManager
	# Verifies actual player attacker combat score scales by tier under controlled seed 12345
	# -------------------------------------------------------------------------
	var off_camp_mgr := BattleCampaignManagerScript.new()
	var off_army_mgr := PlayerArmyManagerScript.new()
	off_army_mgr.soldier_count = 10
	off_army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	off_army_mgr.current_cell = Vector2i(45, 45)
	off_army_mgr.rally_cell = Vector2i(32, 33)
	off_army_mgr.equipment_tier = 1
	off_camp_mgr.set_player_army_manager(off_army_mgr)
	off_camp_mgr.set_custom_world_data(wd)
	off_camp_mgr.set_custom_resource_manager(mock_rm)

	var fm := FactionManagerScript.new()
	var rival_fac = fm.get_faction("rival_military")
	rival_fac.military_power = 50.0
	rival_fac.is_at_war = true
	rival_fac.existence_status = FactionDataScript.STATUS_ACTIVE
	off_camp_mgr.set_faction_manager(fm)

	const CONTROLLED_CAMPAIGN_SEED: int = 12345

	# Tier 1 offensive campaign
	off_army_mgr.equipment_tier = 1
	var off_t1: Dictionary = off_camp_mgr.launch_offensive_campaign("rival_military", CONTROLLED_CAMPAIGN_SEED)
	_assert(off_t1.get("success", false), "TC-EQ.25: Tier 1 offensive campaign launched successfully")
	var rep_t1: BattleResolverScript.BattleReport = off_t1.get("report")
	var score_t1: float = float(rep_t1.details.get("attacker_combat_score", 0.0))
	_assert(score_t1 > 0.0, "TC-EQ.25: Tier 1 attacker combat score generated")

	# Refresh conditions and test Tier 2 with identical seed
	off_army_mgr.soldier_count = 10
	rival_fac.military_power = 50.0
	rival_fac.is_at_war = true
	off_army_mgr.equipment_tier = 2
	var off_t2: Dictionary = off_camp_mgr.launch_offensive_campaign("rival_military", CONTROLLED_CAMPAIGN_SEED)
	_assert(off_t2.get("success", false), "TC-EQ.25: Tier 2 offensive campaign launched successfully")
	var rep_t2: BattleResolverScript.BattleReport = off_t2.get("report")
	var score_t2: float = float(rep_t2.details.get("attacker_combat_score", 0.0))
	_assert(is_equal_approx(score_t2 / score_t1, 1.25), "TC-EQ.25: Attacker combat score with Tier 2 equipment is exactly 1.25x Tier 1 score")

	# Refresh conditions and test Tier 3 with identical seed
	off_army_mgr.soldier_count = 10
	rival_fac.military_power = 50.0
	rival_fac.is_at_war = true
	off_army_mgr.equipment_tier = 3
	var off_t3: Dictionary = off_camp_mgr.launch_offensive_campaign("rival_military", CONTROLLED_CAMPAIGN_SEED)
	_assert(off_t3.get("success", false), "TC-EQ.25: Tier 3 offensive campaign launched successfully")
	var rep_t3: BattleResolverScript.BattleReport = off_t3.get("report")
	var score_t3: float = float(rep_t3.details.get("attacker_combat_score", 0.0))
	_assert(is_equal_approx(score_t3 / score_t1, 1.50), "TC-EQ.25: Attacker combat score with Tier 3 equipment is exactly 1.50x Tier 1 score")

	# -------------------------------------------------------------------------
	# TC-EQ.26: Defensive Raid resolution with mixed defense (recruited army + citizen guards)
	# Verifies composite force construction and actual defensive settlement raid resolution
	# Single consistent rule: Kingdom-wide equipment_tier applies to the total settlement defending force
	# -------------------------------------------------------------------------
	var def_camp_mgr := BattleCampaignManagerScript.new()
	var def_army_mgr := PlayerArmyManagerScript.new()
	def_army_mgr.soldier_count = 6
	def_army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	def_army_mgr.current_cell = def_army_mgr.rally_cell
	def_army_mgr.equipment_tier = 2 # Tier 2 (1.25x)
	def_camp_mgr.set_player_army_manager(def_army_mgr)
	def_camp_mgr.set_custom_world_data(wd)
	def_camp_mgr.set_custom_resource_manager(mock_rm)

	# Mock 2 living citizen guards
	var guard_1 := CitizenControllerScript.new()
	guard_1.citizen_id = "guard_01"
	guard_1.role = "guard"
	guard_1.health = 100.0
	guard_1.morale = 70.0

	var guard_2 := CitizenControllerScript.new()
	guard_2.citizen_id = "guard_02"
	guard_2.role = "guard"
	guard_2.health = 100.0
	guard_2.morale = 70.0

	def_camp_mgr.set_custom_citizen_list([guard_1, guard_2])

	var mixed_def_force: Dictionary = def_camp_mgr.construct_defending_force()
	_assert(mixed_def_force.get("troops") == 8, "TC-EQ.26: Total defending troops = 6 army + 2 guards = 8")
	_assert(mixed_def_force.get("army_soldiers") == 6, "TC-EQ.26: Army soldier sub-count = 6")
	_assert(mixed_def_force.get("guard_count") == 2, "TC-EQ.26: Citizen guard sub-count = 2")
	_assert(mixed_def_force.get("equipment_tier") == 2, "TC-EQ.26: Kingdom-wide equipment tier 2 applies to defending force")

	# Execute real defensive settlement raid resolution with controlled seed 54321
	const DEF_RAID_SEED: int = 54321
	var atk_raid_force: Dictionary = {"troops": 8, "equipment_tier": 1, "morale": 70.0}

	# Resolve settlement battle at Tier 2
	var raid_report_t2: BattleResolverScript.BattleReport = BattleResolverScript.resolve_settlement_battle(
		atk_raid_force,
		mixed_def_force,
		wd,
		DEF_RAID_SEED
	)
	var def_score_t2: float = float(raid_report_t2.details.get("defender_combat_score", 0.0))
	_assert(def_score_t2 > 0.0, "TC-EQ.26: Real defensive raid resolved with positive defender score")

	# Compare with settlement battle at Tier 1 with identical seed and forces
	var mixed_def_t1: Dictionary = mixed_def_force.duplicate(true)
	mixed_def_t1["equipment_tier"] = 1
	var raid_report_t1: BattleResolverScript.BattleReport = BattleResolverScript.resolve_settlement_battle(
		atk_raid_force,
		mixed_def_t1,
		wd,
		DEF_RAID_SEED
	)
	var def_score_t1: float = float(raid_report_t1.details.get("defender_combat_score", 0.0))
	_assert(is_equal_approx(def_score_t2 / def_score_t1, 1.25), "TC-EQ.26: Settlement defense combat score with Tier 2 equipment is exactly 1.25x Tier 1 score")

	guard_1.free()
	guard_2.free()

	# -------------------------------------------------------------------------
	# TC-EQ.27: Tactical strike against SiegeObjectiveActor durability at Tier 1 vs Tier 3
	# (Verifies tactical unit strike damage against fortified outpost; not full FieldSiegeManager campaign)
	# -------------------------------------------------------------------------
	var siege_army_mgr := PlayerArmyManagerScript.new()
	siege_army_mgr.soldier_count = 3
	siege_army_mgr.equipment_tier = 1

	var siege_player_unit := TacticalUnitScript.new()
	siege_player_unit.unit_id = "siege_striker"
	siege_player_unit.faction_id = "player"
	siege_player_unit.attack_damage = 25.0
	siege_player_unit.current_cell = Vector2i(20, 20)
	siege_player_unit.set_player_army_manager(siege_army_mgr)
	world_instance.add_child(siege_player_unit)

	var outpost_objective := SiegeObjectiveActorScript.new()
	outpost_objective.objective_id = "test_outpost_obj"
	outpost_objective.objective_name = "Tiền Đồn Địch"
	outpost_objective.owning_faction_id = "hostile_outpost"
	outpost_objective.max_health = 500.0
	outpost_objective.health = 500.0
	outpost_objective.current_cell = Vector2i(20, 21) # adjacent Manhattan 1
	outpost_objective.is_under_active_siege = true
	world_instance.add_child(outpost_objective)

	# Tier 1 siege attack: deals 25.00 damage
	siege_player_unit.order_attack(outpost_objective)
	siege_player_unit.attack_cooldown_remaining = 0.0
	var hp_before_siege_t1 := outpost_objective.health
	siege_player_unit.advance_combat(0.016, 1.0)
	var siege_dmg_t1 := hp_before_siege_t1 - outpost_objective.health
	_assert(is_equal_approx(siege_dmg_t1, 25.00), "TC-EQ.27: Tier 1 tactical strike dealt exactly 25.00 damage to SiegeObjectiveActor")

	# Upgrade to Tier 3: deals 37.50 damage
	siege_army_mgr.equipment_tier = 3
	siege_player_unit.attack_cooldown_remaining = 0.0
	var hp_before_siege_t3 := outpost_objective.health
	siege_player_unit.advance_combat(0.016, 1.0)
	var siege_dmg_t3 := hp_before_siege_t3 - outpost_objective.health
	_assert(is_equal_approx(siege_dmg_t3, 37.50), "TC-EQ.27: Tier 3 tactical strike dealt exactly 37.50 damage (1.50x) to SiegeObjectiveActor")
	_assert(outpost_objective.health < hp_before_siege_t3, "TC-EQ.27: SiegeObjectiveActor HP reduced cleanly")

	siege_player_unit.queue_free()
	outpost_objective.queue_free()
