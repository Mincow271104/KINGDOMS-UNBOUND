extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 2J: Army Equipment Progression & Combat Integration
## Covers TC-EQ.01 through TC-EQ.21:
## Progression & Economy:
##   TC-EQ.01: Baseline initialization (Tier 1, 1.00x multiplier, name 'Trang bị cơ bản')
##   TC-EQ.02: Upgrade Tier 1 -> Tier 2 (cost 30 Wood, 15 Metal -> 1.25x multiplier, signal emitted)
##   TC-EQ.03: Upgrade Tier 2 -> Tier 3 (cost 60 Wood, 30 Metal -> 1.50x multiplier, signal emitted)
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
## Combat Integration:
##   TC-EQ.14: BattleResolver offensive campaign reflects tier multiplier
##   TC-EQ.15: BattleResolver defensive raid reflects tier multiplier
##   TC-EQ.16: TacticalUnit effective damage scales by tier without mutating base attack_damage
##   TC-EQ.17: EnemyTacticalUnit does NOT inherit player tier multiplier
## Persistence & UI:
##   TC-EQ.18: Save/Load roundtrip preserves Tier 1, 2, 3 and restores identically
##   TC-EQ.19: SaveManager validation rejects invalid/corrupt equipment_tier fail-closed
##   TC-EQ.20: Legacy save lacking equipment_tier defaults smoothly to Tier 1
##   TC-EQ.21: HUD ArmyPanel displays tier standard, multiplier, and upgrade button state

const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

class MockResourceManager:
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
		return true

	func commit_cost(cost: Dictionary) -> void:
		commit_calls += 1
		for res_id in cost:
			var amt: int = cost[res_id]
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - amt)
			stock[res_id] = maxi(0, stock.get(res_id, 0) - amt)

	func release_cost(cost: Dictionary) -> void:
		for res_id in cost:
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - cost[res_id])

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
			print("  PACKAGE 2J ACCEPTANCE TESTS: ALL PASSED!")
		else:
			printerr("  PACKAGE 2J ACCEPTANCE TESTS: %d FAILURE(S) ENCOUNTERED" % failures)
		print("========================================================\n")
		quit(failures)
	return false

func _assert(condition: bool, test_name: String, error_msg: String = "") -> void:
	if condition:
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		var extra := (" - " + error_msg) if not error_msg.is_empty() else ""
		printerr("  [FAIL] %s%s" % [test_name, extra])

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
	# -------------------------------------------------------------------------
	var base_save: Dictionary = {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"metadata": {"world_id": "test_world"},
		"resources": {},
		"buildings": [],
		"citizens": []
	}

	var test_save_t0: Dictionary = base_save.duplicate(true)
	test_save_t0["player_army"] = {"soldier_count": 2, "equipment_tier": 0}
	var v_t0: Dictionary = SaveManagerScript.validate_save_data(test_save_t0)
	_assert(not v_t0.get("valid", true), "TC-EQ.19: SaveManager rejects equipment_tier 0")

	var test_save_t4: Dictionary = base_save.duplicate(true)
	test_save_t4["player_army"] = {"soldier_count": 2, "equipment_tier": 4}
	var v_t4: Dictionary = SaveManagerScript.validate_save_data(test_save_t4)
	_assert(not v_t4.get("valid", true), "TC-EQ.19: SaveManager rejects equipment_tier 4")

	var test_save_str: Dictionary = base_save.duplicate(true)
	test_save_str["player_army"] = {"soldier_count": 2, "equipment_tier": "two"}
	var v_str: Dictionary = SaveManagerScript.validate_save_data(test_save_str)
	_assert(not v_str.get("valid", true), "TC-EQ.19: SaveManager rejects string equipment_tier")

	var test_save_float: Dictionary = base_save.duplicate(true)
	test_save_float["player_army"] = {"soldier_count": 2, "equipment_tier": 2.5}
	var v_float: Dictionary = SaveManagerScript.validate_save_data(test_save_float)
	_assert(not v_float.get("valid", true), "TC-EQ.19: SaveManager rejects non-integer float equipment_tier")

	var test_save_valid: Dictionary = base_save.duplicate(true)
	test_save_valid["player_army"] = {"soldier_count": 2, "equipment_tier": 2}
	var v_valid: Dictionary = SaveManagerScript.validate_save_data(test_save_valid)
	_assert(v_valid.get("valid", false), "TC-EQ.19: SaveManager accepts valid equipment_tier 2")

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
