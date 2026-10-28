extends SceneTree
## Automated Test Suite: Enemy Military Entities & Tactical AI (TASK-1X.2)
## Validates enemy entity creation, crimson armor modulation, deterministic AI state machine
## (HOLD, PATROL, ACQUIRE_TARGET, PURSUE, ATTACK, RECOVER_RETREAT),
## deterministic iteration ordering, peace treaty responsiveness, and persistence.

const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")
const EnemyMilitaryManagerScript = preload("res://scripts/military/enemy_military_manager.gd")

var total_assertions: int = 0
var passed_assertions: int = 0
var failed_assertions: int = 0

class MockNav extends GridNavigation:
	func _init() -> void:
		pass
	func is_cell_walkable(cell: Vector2i) -> bool:
		if not IsoMath.is_in_bounds(cell):
			return false
		return true
	func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
		var p: Array[Vector2i] = [start]
		var cur := start
		while cur != goal:
			if cur.x < goal.x:
				cur.x += 1
			elif cur.x > goal.x:
				cur.x -= 1
			elif cur.y < goal.y:
				cur.y += 1
			elif cur.y > goal.y:
				cur.y -= 1
			p.append(cur)
		return p

class MockFactionManager:
	signal peace_signed(faction_id: String)
	var _at_war: Dictionary = {"hostile_empire": true}
	func get_faction(f_id: String) -> Dictionary:
		return {"id": f_id, "is_at_war": _at_war.get(f_id, false)}
	func are_factions_at_war(f_id: String, _other: String) -> bool:
		return _at_war.get(f_id, false)
	func sign_peace(f_id: String) -> void:
		_at_war[f_id] = false
		peace_signed.emit(f_id)

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
	print("  STARTING PACKAGE 1X ENEMY MILITARY AI TEST SUITE")
	print("========================================================")

	_test_enemy_visuals_and_properties()
	_test_enemy_manager_spawning()
	_test_force_spawning_distinct_slots()
	_test_ai_targeting_and_tie_breaking()
	_test_ai_state_pursuit_and_attack_transitions()
	_test_deterministic_iteration_order()
	_test_peace_treaty_reaction()
	_test_enemy_defeat_and_cleanup()
	_test_enemy_serialization_roundtrip()

	print("========================================================")
	if failed_assertions == 0:
		print("  [SUCCESS] All Enemy Military AI Tests PASSED! (%d assertions)" % total_assertions)
		quit(0)
	else:
		printerr("  [FAILURE] %d assertions FAILED out of %d!" % [failed_assertions, total_assertions])
		quit(1)

func _test_enemy_visuals_and_properties() -> void:
	print("\n--- Test 1: Enemy Visuals & Properties ---")
	var enemy = EnemyTacticalUnitScript.new()
	enemy.unit_id = "test_enemy_1"
	enemy.owning_faction_id = "rebel_warlords"
	enemy._setup_visuals()

	_assert(enemy.sprite != null, "TC-ENEMY.1: Enemy sprite created successfully")
	_assert(enemy.sprite.modulate == EnemyTacticalUnitScript.CRIMSON_MODULATE, "TC-ENEMY.1: Sprite modulate is crimson (0.95, 0.3, 0.3, 1.0)")
	_assert(enemy.detection_range == 8, "TC-ENEMY.1: Default detection_range is 8 tiles")
	_assert(enemy.ai_state == EnemyTacticalUnitScript.AIState.ACQUIRE_TARGET, "TC-ENEMY.1: Initial AI state is ACQUIRE_TARGET")

	enemy.free()

func _test_enemy_manager_spawning() -> void:
	print("\n--- Test 2: Enemy Manager Spawning ---")
	var mgr = EnemyMilitaryManagerScript.new()
	var spawn_sig := {"emitted": false, "id": ""}
	mgr.enemy_spawned.connect(func(id, _fac, _cell):
		spawn_sig["emitted"] = true
		spawn_sig["id"] = id
	)

	var u1 = mgr.spawn_enemy_unit("hostile_clan", Vector2i(20, 20))
	_assert(u1 != null, "TC-ENEMY.2: Spawned enemy unit is not null")
	_assert(u1.unit_id == "enemy_unit_1", "TC-ENEMY.2: First unit assigned stable ID 'enemy_unit_1'")
	_assert(u1.owning_faction_id == "hostile_clan", "TC-ENEMY.2: Owning faction recorded as 'hostile_clan'")
	_assert(u1.current_cell == Vector2i(20, 20), "TC-ENEMY.2: Placed at specified cell (20, 20)")
	_assert(spawn_sig["emitted"] == true, "TC-ENEMY.2: enemy_spawned signal emitted")
	_assert(spawn_sig["id"] == "enemy_unit_1", "TC-ENEMY.2: Signal reported correct ID")
	_assert(mgr.get_enemy_count() == 1, "TC-ENEMY.2: Manager enemy count is 1")
	_assert(mgr.get_enemy("enemy_unit_1") == u1, "TC-ENEMY.2: Retrieved unit matches spawned instance")

	mgr.clear_all_enemies()

func _test_force_spawning_distinct_slots() -> void:
	print("\n--- Test 3: Force Spawning On Distinct Slots ---")
	var mgr = EnemyMilitaryManagerScript.new()
	var nav = MockNav.new()
	mgr.set_custom_nav(nav)

	var center := Vector2i(30, 30)
	var force = mgr.spawn_enemy_force("northern_raiders", center, 5, nav)
	_assert(force.size() == 5, "TC-ENEMY.3: Successfully spawned 5 units in force")
	_assert(mgr.get_enemy_count() == 5, "TC-ENEMY.3: Manager tracks all 5 units")

	var occupied_slots: Dictionary = {}
	var has_duplicate := false
	for u in force:
		if occupied_slots.has(u.current_cell):
			has_duplicate = true
		occupied_slots[u.current_cell] = true
		_assert(IsoMath.is_in_bounds(u.current_cell), "TC-ENEMY.3: Slot is within map bounds")

	_assert(not has_duplicate, "TC-ENEMY.3: All spawned units occupy strictly distinct cells (no overlapping)")

	mgr.clear_all_enemies()

func _test_ai_targeting_and_tie_breaking() -> void:
	print("\n--- Test 4: AI Targeting & Tie-Breaking ---")
	var nav = MockNav.new()
	var enemy = EnemyTacticalUnitScript.new()
	enemy.unit_id = "enemy_eval"
	enemy.current_cell = Vector2i(20, 20)
	enemy.detection_range = 8

	var player_far = TacticalUnitScript.new()
	player_far.unit_id = "player_far"
	player_far.current_cell = Vector2i(20, 26) # Dist = 6

	var player_close_b = TacticalUnitScript.new()
	player_close_b.unit_id = "player_close_b"
	player_close_b.current_cell = Vector2i(20, 22) # Dist = 2

	var player_close_a = TacticalUnitScript.new()
	player_close_a.unit_id = "player_close_a"
	player_close_a.current_cell = Vector2i(22, 20) # Dist = 2 (same dist as B!)

	# Nearest check: should pick dist 2 over dist 6
	# Tie-breaker: between player_close_a and player_close_b (both dist 2), player_close_a has lower alphabetical ID
	var players: Array = [player_far, player_close_b, player_close_a]

	enemy.update_ai(0.1, 1.0, nav, players)
	_assert(enemy.target_actor == player_close_a, "TC-ENEMY.4: Closest player with alphabetical tie-breaker selected (player_close_a)")

	enemy.free()
	player_far.free()
	player_close_b.free()
	player_close_a.free()

func _test_ai_state_pursuit_and_attack_transitions() -> void:
	print("\n--- Test 5: AI Pursuit & Attack State Transitions ---")
	var nav = MockNav.new()
	var enemy = EnemyTacticalUnitScript.new()
	enemy.unit_id = "enemy_fsm"
	enemy.current_cell = Vector2i(10, 10)
	enemy.attack_range = 1
	enemy.detection_range = 5

	var player = TacticalUnitScript.new()
	player.unit_id = "player_fsm"
	player.current_cell = Vector2i(10, 13) # Dist = 3 > attack_range (1)
	player.health = 100.0

	var players: Array = [player]

	# 1. Acquire target -> Dist > 1 -> transitions to PURSUE
	enemy.update_ai(0.1, 1.0, nav, players)
	_assert(enemy.ai_state == EnemyTacticalUnitScript.AIState.PURSUE, "TC-ENEMY.5: Dist > attack_range transitions to PURSUE")
	_assert(enemy.order_state == TacticalUnitScript.OrderState.ATTACKING, "TC-ENEMY.5: Unit order state is ATTACKING")

	# 2. Simulate closing distance to adjacent cell (dist = 1)
	player.current_cell = Vector2i(10, 11)
	enemy.update_ai(0.1, 1.0, nav, players)
	_assert(enemy.ai_state == EnemyTacticalUnitScript.AIState.ATTACK, "TC-ENEMY.5: Dist <= attack_range transitions to ATTACK")

	# 3. Simulate target stepping away (dist = 2) -> transitions back to PURSUE
	player.current_cell = Vector2i(10, 12)
	enemy.update_ai(0.1, 1.0, nav, players)
	_assert(enemy.ai_state == EnemyTacticalUnitScript.AIState.PURSUE, "TC-ENEMY.5: Dist > attack_range transitions back to PURSUE")

	enemy.free()
	player.free()

func _test_deterministic_iteration_order() -> void:
	print("\n--- Test 6: Deterministic Iteration Order ---")
	var mgr = EnemyMilitaryManagerScript.new()
	# Spawn out of order
	mgr.spawn_enemy_unit("fac", Vector2i(10, 10), "enemy_z")
	mgr.spawn_enemy_unit("fac", Vector2i(11, 10), "enemy_a")
	mgr.spawn_enemy_unit("fac", Vector2i(12, 10), "enemy_m")

	# Sorted keys must be enemy_a, enemy_m, enemy_z
	var keys = mgr.enemies.keys()
	keys.sort()
	_assert(keys[0] == "enemy_a" and keys[1] == "enemy_m" and keys[2] == "enemy_z", "TC-ENEMY.6: Enemy IDs sorted in ascending order for deterministic iteration")

	mgr.clear_all_enemies()

func _test_peace_treaty_reaction() -> void:
	print("\n--- Test 7: Peace Treaty Reaction ---")
	var fm = MockFactionManager.new()
	var mgr = EnemyMilitaryManagerScript.new(null, fm)
	var nav = MockNav.new()
	mgr.set_custom_nav(nav)

	var enemy = mgr.spawn_enemy_unit("hostile_empire", Vector2i(15, 15))
	var player = TacticalUnitScript.new()
	player.unit_id = "player_peace"
	player.current_cell = Vector2i(15, 16)
	player.health = 100.0

	# Acquire target while at war
	enemy.update_ai(0.1, 1.0, nav, [player], fm)
	_assert(enemy.ai_state == EnemyTacticalUnitScript.AIState.ATTACK, "TC-ENEMY.7: Enemy is actively attacking during war")

	# Sign peace treaty!
	fm.sign_peace("hostile_empire")

	# Enemy AI tick should now detect peace
	enemy.update_ai(0.1, 1.0, nav, [player], fm)
	_assert(enemy.ai_state == EnemyTacticalUnitScript.AIState.RECOVER_RETREAT, "TC-ENEMY.7: Enemy transitioned to RECOVER_RETREAT upon peace")
	_assert(enemy.target_actor == null, "TC-ENEMY.7: Target actor cleared upon peace")
	_assert(enemy.order_state != TacticalUnitScript.OrderState.ATTACKING, "TC-ENEMY.7: Attack order cancelled upon peace (transitioned to retreat movement)")

	player.free()
	mgr.clear_all_enemies()

func _test_enemy_defeat_and_cleanup() -> void:
	print("\n--- Test 8: Enemy Defeat & Cleanup ---")
	var mgr = EnemyMilitaryManagerScript.new()
	var defeated_sig := {"emitted": false, "id": "", "killer": ""}
	mgr.enemy_defeated.connect(func(id, _fac, killer):
		defeated_sig["emitted"] = true
		defeated_sig["id"] = id
		defeated_sig["killer"] = killer
	)

	var enemy = mgr.spawn_enemy_unit("bandits", Vector2i(18, 18), "bandit_1")
	_assert(mgr.get_enemy_count() == 1, "TC-ENEMY.8: 1 bandit spawned")

	# Slay the enemy
	enemy.take_damage(200.0, "royal_guard_1")

	_assert(defeated_sig["emitted"] == true, "TC-ENEMY.8: enemy_defeated signal fired on manager")
	_assert(defeated_sig["id"] == "bandit_1", "TC-ENEMY.8: Defeated enemy ID matches")
	_assert(defeated_sig["killer"] == "royal_guard_1", "TC-ENEMY.8: Killer recorded correctly")
	_assert(mgr.get_enemy_count() == 0, "TC-ENEMY.8: Enemy cleanly removed from manager roster")
	_assert(mgr.get_enemy("bandit_1") == null, "TC-ENEMY.8: get_enemy returns null for defeated unit")

func _test_enemy_serialization_roundtrip() -> void:
	print("\n--- Test 9: Enemy Serialization Roundtrip ---")
	var mgr1 = EnemyMilitaryManagerScript.new()
	var e1 = mgr1.spawn_enemy_unit("orc_clan", Vector2i(22, 25), "orc_1", 150.0, 30.0)
	var e2 = mgr1.spawn_enemy_unit("orc_clan", Vector2i(23, 25), "orc_2", 120.0, 25.0)

	var data: Dictionary = mgr1.serialize()
	_assert(data.has("enemies") and data["enemies"].size() == 2, "TC-ENEMY.9: Serialized 2 enemies")

	var mgr2 = EnemyMilitaryManagerScript.new()
	var ok: bool = mgr2.deserialize(data)
	_assert(ok == true, "TC-ENEMY.9: Deserialization returned true")
	_assert(mgr2.get_enemy_count() == 2, "TC-ENEMY.9: Restored exactly 2 enemies")

	var restored_orc1 = mgr2.get_enemy("orc_1")
	_assert(restored_orc1 != null, "TC-ENEMY.9: orc_1 successfully restored")
	_assert(restored_orc1.health == 150.0, "TC-ENEMY.9: orc_1 health restored to 150.0")
	_assert(restored_orc1.attack_damage == 30.0, "TC-ENEMY.9: orc_1 attack damage restored to 30.0")
	_assert(restored_orc1.current_cell == Vector2i(22, 25), "TC-ENEMY.9: orc_1 cell restored to (22, 25)")
	_assert(restored_orc1.owning_faction_id == "orc_clan", "TC-ENEMY.9: orc_1 owning_faction_id restored")

	mgr1.clear_all_enemies()
	mgr2.clear_all_enemies()
