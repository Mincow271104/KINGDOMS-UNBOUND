extends SceneTree
## Test Suite: Session 1.1 Targeted Military Invariant Corrections
## Validates:
## 1. Congested base atomic fail-closed eviction & demolition protection
## 2. All production territorial outpost destruction & conquest paths
## 3. Legacy save load without ID counters & subsequent ID uniqueness
## 4. Distinct evaluation of Invariant A (total headcount) & Invariant B (central unit equality)

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")

var frame_count: int = 0
var tests_executed: bool = false
var failures: int = 0
var passed_count: int = 0
var world_instance: Node = null

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 1.1 TARGETED CORRECTIONS TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 4242
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count >= 3 and not tests_executed:
		tests_executed = true
		_run_all_tests()
	return false

# Helper mock for congestion simulation
class MockCongestionTMM extends RefCounted:
	var units: Dictionary = {}
	var should_refuse_spawns: bool = true
	var real_tmm: Object = null

	func _init(p_real_tmm: Object) -> void:
		real_tmm = p_real_tmm
		if real_tmm != null and "units" in real_tmm:
			units = real_tmm.units

	func can_allocate_spawns(_count: int, _rally_cell: Vector2i = Vector2i(-1, -1)) -> bool:
		if should_refuse_spawns:
			return false
		if real_tmm != null and real_tmm.has_method("can_allocate_spawns"):
			return bool(real_tmm.call("can_allocate_spawns", _count, _rally_cell))
		return true

	func sync_with_player_army(_pref: bool = false, _loc: bool = false) -> void:
		if real_tmm != null and real_tmm.has_method("sync_with_player_army"):
			real_tmm.call("sync_with_player_army", _pref, _loc)

	func get_occupied_cells() -> Array[Vector2i]:
		if real_tmm != null and real_tmm.has_method("get_occupied_cells"):
			return real_tmm.call("get_occupied_cells")
		return []

func _create_active_watchtower(b_id: String, cell: Vector2i) -> Dictionary:
	var wd = world_instance.world_data
	var b_data := {
		"id": b_id,
		"type": "watchtower",
		"cell": cell,
		"size": Vector2i(1, 1),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[cell] = b_data
	world_instance._instantiate_building_node("watchtower", cell, Vector2i(1, 1), "active")
	return b_data

func _calc_invariants(pam: PlayerArmyManager, tmm: Object) -> Dictionary:
	var central: int = pam.soldier_count
	var all_gar: int = pam.get_all_garrisoned_count()
	var in_transit: int = pam.get_in_transit_count()
	var total_headcount: int = central + all_gar + in_transit
	var tactical_unit_count: int = tmm.units.size()
	return {
		"central_reserve": central,
		"garrisoned": all_gar,
		"in_transit": in_transit,
		"total_headcount": total_headcount,
		"tactical_units": tactical_unit_count,
		"tactical_equality": (tactical_unit_count == central)
	}

func _run_all_tests() -> void:
	var pam = world_instance.player_army_mgr
	var tmm = world_instance.tactical_military_mgr
	var fsm = world_instance.field_siege_mgr
	var wd = world_instance.world_data

	_assert(pam != null and tmm != null and fsm != null and wd != null, "Managers initialized")

	# Base setup: 10 soldiers
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	var inv0 := _calc_invariants(pam, tmm)
	_assert(inv0.total_headcount == 10, "Base Invariant A: Total headcount is 10")
	_assert(inv0.tactical_equality == true, "Base Invariant B: Tactical units (10) == Central reserve (10)")

	# =========================================================================
	# GROUP 1: Involuntary Eviction Spawn Congestion Fail-Closed Protection
	# =========================================================================
	print("\n--- GROUP 1: Involuntary Eviction Spawn Congestion Protection ---")

	# 1A: Setup watchtower with 1 garrison and 1 reinforcement
	_create_active_watchtower("bld_watchtower_c1", Vector2i(10, 10))
	pam.station_soldier("bld_watchtower_c1", 1)
	pam.dispatch_reinforcements("bld_watchtower_c1", 1, 4.0)
	var inv1_before := _calc_invariants(pam, tmm)
	_assert(inv1_before.central_reserve == 8, "Central reserve reduced to 8")
	_assert(inv1_before.garrisoned == 1, "Garrison count is 1")
	_assert(inv1_before.in_transit == 1, "In-transit count is 1")
	_assert(inv1_before.total_headcount == 10, "Invariant A holds: 8 + 1 + 1 = 10")
	_assert(inv1_before.tactical_equality == true, "Invariant B holds: 8 units == 8 reserve")

	# Attach mock congestion manager
	var mock_tmm := MockCongestionTMM.new(tmm)
	pam.tactical_military_mgr = mock_tmm
	world_instance.tactical_military_mgr = mock_tmm

	# 1B: Attempt evict_and_cancel_outpost under congestion
	var evict_fail: Dictionary = pam.evict_and_cancel_outpost("bld_watchtower_c1", true)
	_assert(evict_fail.get("success", true) == false, "TC-1.1.1: evict_and_cancel_outpost rejected fail-closed under congestion")
	_assert(pam.garrisons.has("bld_watchtower_c1"), "TC-1.1.2: Garrison records untouched on failed eviction")
	_assert(pam.get_in_transit_count("bld_watchtower_c1") == 1, "TC-1.1.3: In-transit records untouched on failed eviction")
	var inv1_mid := _calc_invariants(pam, tmm)
	_assert(inv1_mid.central_reserve == 8, "TC-1.1.4: Central reserve untouched at 8")
	_assert(inv1_mid.total_headcount == 10, "TC-1.1.5: Invariant A preserved (10 total)")
	_assert(inv1_mid.tactical_equality == true, "TC-1.1.6: Invariant B preserved (8 == 8)")

	# 1C: Attempt demolition under congestion
	var demo_fail: Dictionary = world_instance.demolish_building_project("bld_watchtower_c1")
	_assert(demo_fail.get("success", true) == false, "TC-1.1.7: demolish_building_project rejected fail-closed under congestion")
	_assert(not BuildingSystemScript.get_building_by_id("bld_watchtower_c1", wd).is_empty(), "TC-1.1.8: Building NOT demolished on congestion rejection")
	_assert(pam.garrisons.has("bld_watchtower_c1"), "TC-1.1.9: Garrison preserved in building")

	# 1D: Restore unblocked state and complete eviction
	mock_tmm.should_refuse_spawns = false
	pam.tactical_military_mgr = tmm
	world_instance.tactical_military_mgr = tmm
	var evict_ok: Dictionary = pam.evict_and_cancel_outpost("bld_watchtower_c1", true)
	_assert(evict_ok.get("success", false) == true, "TC-1.1.10: Eviction succeeds when spawn slots unblocked")
	var inv1_after := _calc_invariants(pam, tmm)
	_assert(inv1_after.central_reserve == 10, "TC-1.1.11: 2 soldiers refunded to central reserve (10)")
	_assert(inv1_after.total_headcount == 10, "TC-1.1.12: Invariant A strictly conserved at 10")
	_assert(inv1_after.tactical_equality == true, "TC-1.1.13: Invariant B strictly conserved (10 units == 10 reserve)")

	world_instance.demolish_building_project("bld_watchtower_c1")

	# =========================================================================
	# GROUP 2: Production Territorial Outpost Lifecycle (FieldSiegeManager)
	# =========================================================================
	print("\n--- GROUP 2: Production Territorial Outpost Lifecycle ---")

	# Register a territorial outpost objective in FieldSiegeManager
	var obj_id := "obj_territory_alpha"
	fsm.register_objective(obj_id, Vector2i(15, 15), "player", 100, 3)
	pam.register_outpost_for_testing(obj_id, 3, Vector2i(15, 15), "player")

	# 2A: Station 1 soldier, dispatch 1 reinforcement
	pam.station_soldier(obj_id, 1)
	pam.dispatch_reinforcements(obj_id, 1, 5.0)
	var inv2_pre := _calc_invariants(pam, tmm)
	_assert(inv2_pre.central_reserve == 8, "TC-1.2.1: Central reserve is 8")
	_assert(inv2_pre.garrisoned == 1, "TC-1.2.2: Stationed count is 1")
	_assert(inv2_pre.in_transit == 1, "TC-1.2.3: In-transit count is 1")
	_assert(inv2_pre.total_headcount == 10, "TC-1.2.4: Invariant A holds: 8 + 1 + 1 = 10")
	_assert(inv2_pre.tactical_equality == true, "TC-1.2.5: Invariant B holds: 8 units == 8 reserve")

	# 2B: Territorial outpost destruction via objective_destroyed signal
	fsm.objective_destroyed.emit(obj_id, "enemy_raider")
	var inv2_post_dest := _calc_invariants(pam, tmm)
	_assert(not pam.garrisons.has(obj_id), "TC-1.2.6: Garrison evicted on territorial outpost destruction")
	_assert(pam.get_in_transit_count(obj_id) == 0, "TC-1.2.7: In-transit reinforcements cancelled on destruction")
	_assert(inv2_post_dest.central_reserve == 10, "TC-1.2.8: 2 soldiers returned to central reserve (10)")
	_assert(inv2_post_dest.total_headcount == 10, "TC-1.2.9: Invariant A conserved (10 total)")
	_assert(inv2_post_dest.tactical_equality == true, "TC-1.2.10: Invariant B conserved (10 units == 10 reserve)")

	# 2C: Repeated destruction callback idempotency
	fsm.objective_destroyed.emit(obj_id, "enemy_raider")
	var inv2_repeat := _calc_invariants(pam, tmm)
	_assert(inv2_repeat.central_reserve == 10, "TC-1.2.11: Repeated destruction callback does not duplicate refund")
	_assert(inv2_repeat.tactical_equality == true, "TC-1.2.12: Tactical equality strictly preserved on repeat")

	# 2D: Territorial outpost ownership transfer / conquest path
	var obj_beta := "obj_territory_beta"
	fsm.register_objective(obj_beta, Vector2i(25, 25), "player", 100, 3)
	pam.register_outpost_for_testing(obj_beta, 3, Vector2i(25, 25), "player")
	pam.station_soldier(obj_beta, 1)
	pam.dispatch_reinforcements(obj_beta, 1, 5.0)
	var inv2_beta_pre := _calc_invariants(pam, tmm)
	_assert(inv2_beta_pre.total_headcount == 10, "Pre-transfer total headcount is 10")

	# Enemy captures outpost
	var tx_res: Dictionary = fsm.transfer_outpost_ownership(obj_beta, "rival_military", "tx_conquest_01")
	_assert(tx_res.get("success", false) == true, "TC-1.2.13: transfer_outpost_ownership succeeded")
	var inv2_beta_post := _calc_invariants(pam, tmm)
	_assert(not pam.garrisons.has(obj_beta), "TC-1.2.14: Garrison evicted on ownership transfer")
	_assert(pam.get_in_transit_count(obj_beta) == 0, "TC-1.2.15: In-transit reinforcements cancelled on ownership transfer")
	_assert(inv2_beta_post.central_reserve == 10, "TC-1.2.16: Both soldiers safely returned to central reserve (10)")
	_assert(inv2_beta_post.total_headcount == 10, "TC-1.2.17: Invariant A conserved on conquest (10 total)")
	_assert(inv2_beta_post.tactical_equality == true, "TC-1.2.18: Invariant B conserved on conquest (10 units == 10 reserve)")

	# =========================================================================
	# GROUP 3: Legacy Save Deserialization Without ID Counters & ID Uniqueness
	# =========================================================================
	print("\n--- GROUP 3: Legacy Save Compatibility & ID Uniqueness ---")

	# Construct a raw legacy dictionary omitting next_soldier_id and next_reinforce_id
	var legacy_save_data: Dictionary = {
		"garrisons": {
			"outpost_legacy_1": {
				"outpost_id": "outpost_legacy_1",
				"capacity": 3,
				"soldiers": [
					{"soldier_id": "soldier_gar_12", "equipment_tier": 1, "health": 100},
					{"soldier_id": "soldier_gar_15", "equipment_tier": 1, "health": 100}
				]
			}
		},
		"reinforcements": [
			{
				"dispatch_id": "reinf_8",
				"outpost_id": "outpost_legacy_1",
				"soldier_count": 1,
				"soldiers": [
					{"soldier_id": "soldier_reinf_19", "equipment_tier": 1, "health": 100}
				],
				"travel_hours": 3.0,
				"elapsed_hours": 0.0
			}
		]
	}

	# Clean pam state and deserialize pure legacy data
	pam.garrisons.clear()
	pam.active_reinforcements.clear()
	var deser_ok: bool = pam.deserialize_garrisons(legacy_save_data)
	_assert(deser_ok == true, "TC-1.3.1: deserialize_garrisons succeeded on legacy data without counters")

	# Verify max ID recomputation
	_assert(pam.next_soldier_id >= 20, "TC-1.3.2: next_soldier_id recomputed > max(12, 15, 19) -> got %d" % pam.next_soldier_id)
	_assert(pam.next_reinforce_id >= 9, "TC-1.3.3: next_reinforce_id recomputed > max(8) -> got %d" % pam.next_reinforce_id)

	# Verify stationing post-legacy-load creates unique ID
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_legacy_1", 5, Vector2i(10, 10), "player")
	var stat_legacy: Dictionary = pam.station_soldier("outpost_legacy_1", 1)
	_assert(stat_legacy.get("success", false) == true, "TC-1.3.4: station_soldier succeeded post-legacy-load")
	var new_s_id: String = pam.garrisons["outpost_legacy_1"]["soldiers"][-1].get("soldier_id", "")
	_assert(new_s_id != "soldier_gar_12" and new_s_id != "soldier_gar_15" and new_s_id != "soldier_reinf_19",
		"TC-1.3.5: New soldier ID (%s) is strictly unique from all loaded IDs" % new_s_id)

	# Verify dispatch post-legacy-load creates unique ID
	var disp_legacy: Dictionary = pam.dispatch_reinforcements("outpost_legacy_1", 1, 2.0)
	_assert(disp_legacy.get("success", false) == true, "TC-1.3.6: dispatch_reinforcements succeeded post-legacy-load")
	var new_disp_id: String = disp_legacy.get("dispatch_id", "")
	_assert(new_disp_id != "reinf_8", "TC-1.3.7: New dispatch ID (%s) is strictly unique from loaded 'reinf_8'" % new_disp_id)

	print("\n--------------------------------------------------------")
	print("  SESSION 1.1 RESULTS: %d Passed, %d Failed" % [passed_count, failures])
	print("--------------------------------------------------------\n")
	quit(0 if failures == 0 else 1)
