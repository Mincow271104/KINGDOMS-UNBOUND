extends SceneTree
## Automated Test Suite: Real-Time Tactical Combat (TASK-1X.1)
## Validates data-driven combat model, health bars, Manhattan range checking,
## attack cooldowns, damage application, friendly fire rejection,
## TimeManager pause/speed compliance, and strict casualty parity with PlayerArmyManager.

const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")

var total_assertions: int = 0
var passed_assertions: int = 0
var failed_assertions: int = 0

class MockTimeManager:
	var _paused: bool = false
	var current_speed: float = 1.0
	func is_paused() -> bool:
		return _paused
	func set_paused(p: bool) -> void:
		_paused = p

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
	print("  STARTING PACKAGE 1X TACTICAL COMBAT TEST SUITE")
	print("========================================================")

	_test_combat_stat_initialization()
	_test_take_damage_and_flash()
	_test_lethal_damage_and_defeat_signal()
	_test_friendly_fire_rejection()
	_test_order_attack_and_target_assignment()
	_test_range_checking_and_strike_resolution()
	_test_cooldown_enforcement()
	_test_time_manager_pause_and_speed_scaling()
	_test_dead_target_auto_disengage()
	_test_casualty_parity_with_player_army()
	_test_combat_serialization_roundtrip()

	print("========================================================")
	if failed_assertions == 0:
		print("  [SUCCESS] All Tactical Combat Tests PASSED! (%d assertions)" % total_assertions)
		quit(0)
	else:
		printerr("  [FAILURE] %d assertions FAILED out of %d!" % [failed_assertions, total_assertions])
		quit(1)

func _test_combat_stat_initialization() -> void:
	print("\n--- Test 1: Combat Stat Initialization ---")
	var unit = TacticalUnitScript.new()
	unit.unit_id = "test_player_1"
	unit.current_cell = Vector2i(10, 10)

	_assert(unit.health == 100.0, "TC-COMBAT.1: Default health is 100.0")
	_assert(unit.max_health == 100.0, "TC-COMBAT.1: Default max_health is 100.0")
	_assert(unit.attack_damage == 25.0, "TC-COMBAT.1: Default attack_damage is 25.0")
	_assert(unit.attack_range == 1, "TC-COMBAT.1: Default attack_range is 1")
	_assert(unit.attack_cooldown == 1.2, "TC-COMBAT.1: Default attack_cooldown is 1.2")
	_assert(unit.attack_cooldown_remaining == 0.0, "TC-COMBAT.1: Cooldown starts at 0.0")
	_assert(unit.is_alive == true, "TC-COMBAT.1: Unit is_alive is initially true")
	_assert(unit.faction_id == "player", "TC-COMBAT.1: Default faction_id is 'player'")
	unit.free()

func _test_take_damage_and_flash() -> void:
	print("\n--- Test 2: Take Damage & Flash Indicator ---")
	var unit = TacticalUnitScript.new()
	unit.unit_id = "test_player_2"
	var res := {"emitted": false, "damage": 0.0}

	unit.unit_took_damage.connect(func(_id, amt, _hp, _max):
		res["emitted"] = true
		res["damage"] = amt
	)

	unit.take_damage(30.0, "attacker_1")
	_assert(unit.health == 70.0, "TC-COMBAT.2: Health reduced from 100 to 70 after 30 damage")
	_assert(res["emitted"], "TC-COMBAT.2: unit_took_damage signal was emitted")
	_assert(res["damage"] == 30.0, "TC-COMBAT.2: Signal reported correct damage amount (30)")
	_assert(unit.damage_flash_timer > 0.0, "TC-COMBAT.2: Visual damage flash timer activated")
	_assert(unit.is_alive == true, "TC-COMBAT.2: Unit remains alive at 70 HP")
	unit.free()

func _test_lethal_damage_and_defeat_signal() -> void:
	print("\n--- Test 3: Lethal Damage & Defeat Signal ---")
	var unit = TacticalUnitScript.new()
	unit.unit_id = "test_player_3"
	var res := {"emitted": false, "killer": ""}

	unit.unit_defeated.connect(func(_id, killer):
		res["emitted"] = true
		res["killer"] = killer
	)

	unit.take_damage(120.0, "enemy_boss")
	_assert(unit.health == 0.0, "TC-COMBAT.3: Health clamped to 0.0 upon overkill damage")
	_assert(unit.is_alive == false, "TC-COMBAT.3: is_alive set to false")
	_assert(res["emitted"], "TC-COMBAT.3: unit_defeated signal emitted")
	_assert(res["killer"] == "enemy_boss", "TC-COMBAT.3: Killer correctly recorded as 'enemy_boss'")
	_assert(unit.order_state == TacticalUnitScript.OrderState.IDLE, "TC-COMBAT.3: Defeated unit resets to IDLE")

	# Idempotency check: further damage to dead unit does nothing
	res["emitted"] = false
	unit.take_damage(50.0, "another_killer")
	_assert(not res["emitted"], "TC-COMBAT.3: Dead unit does not re-emit unit_defeated")
	unit.free()

func _test_friendly_fire_rejection() -> void:
	print("\n--- Test 4: Friendly Fire Rejection ---")
	var player_a = TacticalUnitScript.new()
	player_a.unit_id = "player_a"
	player_a.faction_id = "player"

	var player_b = TacticalUnitScript.new()
	player_b.unit_id = "player_b"
	player_b.faction_id = "player"

	var enemy_u = EnemyTacticalUnitScript.new()
	enemy_u.unit_id = "enemy_1"
	enemy_u.owning_faction_id = "hostile_faction"
	enemy_u.faction_id = "hostile_faction"

	_assert(not player_a.can_attack_target(player_b), "TC-COMBAT.4: Player unit cannot attack another player unit")
	_assert(player_a.can_attack_target(enemy_u), "TC-COMBAT.4: Player unit can attack hostile enemy unit")
	_assert(enemy_u.can_attack_target(player_a), "TC-COMBAT.4: Enemy unit can attack player unit")

	player_a.free()
	player_b.free()
	enemy_u.free()

func _test_order_attack_and_target_assignment() -> void:
	print("\n--- Test 5: Order Attack & Target Assignment ---")
	var player_u = TacticalUnitScript.new()
	player_u.unit_id = "player_u"
	player_u.faction_id = "player"

	var enemy_u = EnemyTacticalUnitScript.new()
	enemy_u.unit_id = "enemy_target"
	enemy_u.owning_faction_id = "enemy_fac"
	enemy_u.faction_id = "enemy_fac"

	player_u.order_attack(enemy_u)
	_assert(player_u.order_state == TacticalUnitScript.OrderState.ATTACKING, "TC-COMBAT.5: OrderState transitions to ATTACKING")
	_assert(player_u.target_actor == enemy_u, "TC-COMBAT.5: target_actor set to target node")
	_assert(player_u.target_actor_id == "enemy_target", "TC-COMBAT.5: target_actor_id set to 'enemy_target'")

	player_u.free()
	enemy_u.free()

func _test_range_checking_and_strike_resolution() -> void:
	print("\n--- Test 6: Range Checking & Strike Resolution ---")
	var nav = MockNav.new()
	var player_u = TacticalUnitScript.new()
	player_u.unit_id = "player_striker"
	player_u.current_cell = Vector2i(10, 10)
	player_u.attack_range = 1
	player_u.attack_damage = 30.0
	player_u.attack_cooldown = 1.0
	player_u.attack_cooldown_remaining = 0.0

	var enemy_u = EnemyTacticalUnitScript.new()
	enemy_u.unit_id = "enemy_target"
	enemy_u.current_cell = Vector2i(10, 11) # Manhattan distance = 1 (in range!)
	enemy_u.health = 100.0

	player_u.order_attack(enemy_u)

	var res := {"fired": false}
	player_u.unit_attacked.connect(func(_atk, _tgt, _dmg):
		res["fired"] = true
	)

	# In range: advance combat by 0.1s
	player_u.advance_combat(0.1, 1.0, nav)
	_assert(res["fired"], "TC-COMBAT.6: Attack strike executed when in range")
	_assert(enemy_u.health == 70.0, "TC-COMBAT.6: Target took 30 damage (health 100 -> 70)")
	_assert(player_u.attack_cooldown_remaining > 0.8, "TC-COMBAT.6: Cooldown was reset after strike")

	player_u.free()
	enemy_u.free()

func _test_cooldown_enforcement() -> void:
	print("\n--- Test 7: Cooldown Enforcement ---")
	var nav = MockNav.new()
	var player_u = TacticalUnitScript.new()
	player_u.unit_id = "player_cooldown"
	player_u.current_cell = Vector2i(10, 10)
	player_u.attack_range = 1
	player_u.attack_damage = 20.0
	player_u.attack_cooldown = 1.0
	player_u.attack_cooldown_remaining = 0.8 # Cooldown still active!

	var enemy_u = EnemyTacticalUnitScript.new()
	enemy_u.unit_id = "enemy_cooldown"
	enemy_u.current_cell = Vector2i(10, 11)
	enemy_u.health = 100.0

	player_u.order_attack(enemy_u)
	player_u.advance_combat(0.3, 1.0, nav) # Remaining becomes 0.5s > 0

	_assert(enemy_u.health == 100.0, "TC-COMBAT.7: No damage dealt while cooldown is active")
	_assert(player_u.attack_cooldown_remaining == 0.5, "TC-COMBAT.7: Cooldown remaining decremented by 0.3 to 0.5")

	# Advance remaining 0.6s -> cooldown expires and strike occurs
	player_u.advance_combat(0.6, 1.0, nav)
	_assert(enemy_u.health == 80.0, "TC-COMBAT.7: Strike executed once cooldown expired")

	player_u.free()
	enemy_u.free()

func _test_time_manager_pause_and_speed_scaling() -> void:
	print("\n--- Test 8: TimeManager Pause & Speed Scaling ---")
	var tm = MockTimeManager.new()
	var nav = MockNav.new()
	var unit = TacticalUnitScript.new()
	unit.set_custom_time_manager(tm)
	unit.current_cell = Vector2i(5, 5)
	unit.attack_range = 1
	unit.attack_damage = 25.0
	unit.attack_cooldown = 1.0
	unit.attack_cooldown_remaining = 0.5

	var enemy = EnemyTacticalUnitScript.new()
	enemy.current_cell = Vector2i(5, 6)
	enemy.health = 100.0
	unit.order_attack(enemy)

	# 1. When paused: combat does not advance
	tm.set_paused(true)
	unit.advance_combat(1.0, 1.0, nav)
	_assert(unit.attack_cooldown_remaining == 0.5, "TC-COMBAT.8: Combat cooldown strictly frozen when paused")
	_assert(enemy.health == 100.0, "TC-COMBAT.8: No damage dealt when paused")

	# 2. When unpaused at 2x speed: cooldown advances twice as fast
	tm.set_paused(false)
	unit.advance_combat(0.25, 2.0, nav) # 0.25 * 2.0 = 0.5 elapsed, cooldown expires!
	_assert(enemy.health == 75.0, "TC-COMBAT.8: 2x simulation speed scaled strike successfully")

	unit.free()
	enemy.free()

func _test_dead_target_auto_disengage() -> void:
	print("\n--- Test 9: Dead Target Auto-Disengage ---")
	var nav = MockNav.new()
	var player_u = TacticalUnitScript.new()
	player_u.current_cell = Vector2i(10, 10)
	var enemy_u = EnemyTacticalUnitScript.new()
	enemy_u.current_cell = Vector2i(10, 11)
	enemy_u.health = 10.0

	player_u.order_attack(enemy_u)
	_assert(player_u.order_state == TacticalUnitScript.OrderState.ATTACKING, "TC-COMBAT.9: Initial state is ATTACKING")

	# Kill the target
	enemy_u.take_damage(50.0)
	_assert(enemy_u.is_alive == false, "TC-COMBAT.9: Target is dead")

	# Advance combat
	player_u.advance_combat(0.1, 1.0, nav)
	_assert(player_u.order_state == TacticalUnitScript.OrderState.IDLE, "TC-COMBAT.9: Attacker automatically returned to IDLE")
	_assert(player_u.target_actor == null, "TC-COMBAT.9: target_actor cleared")
	_assert(player_u.target_actor_id == "", "TC-COMBAT.9: target_actor_id cleared")

	player_u.free()
	enemy_u.free()

func _test_casualty_parity_with_player_army() -> void:
	print("\n--- Test 10: Strict Casualty Parity with PlayerArmyManager ---")
	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)

	# Set up 3 soldiers
	army_mgr.soldier_count = 3
	tac_mgr.sync_with_player_army()
	_assert(tac_mgr.get_unit_count() == 3, "TC-COMBAT.10: Roster has 3 units initially")
	_assert(army_mgr.soldier_count == 3, "TC-COMBAT.10: PlayerArmyManager has 3 soldiers")

	# Defeat 1 tactical unit in combat
	var units_list = tac_mgr.get_all_units()
	var unit_to_kill = units_list[0]
	var killed_id: String = unit_to_kill.unit_id

	unit_to_kill.take_damage(200.0, "hostile_swordsman")

	_assert(tac_mgr.get_unit_count() == 2, "TC-COMBAT.10: Tactical roster decremented to 2")
	_assert(army_mgr.soldier_count == 2, "TC-COMBAT.10: PlayerArmyManager soldier_count decremented to 2")
	_assert(tac_mgr.get_unit(killed_id) == null, "TC-COMBAT.10: Defeated unit erased from tactical roster")

	# Defeat the remaining 2 units
	var remaining = tac_mgr.get_all_units()
	remaining[0].take_damage(200.0, "hostile_swordsman")
	remaining[1].take_damage(200.0, "hostile_swordsman")

	_assert(tac_mgr.get_unit_count() == 0, "TC-COMBAT.10: Roster reduced to 0 units")
	_assert(army_mgr.soldier_count == 0, "TC-COMBAT.10: Strategic soldier_count reduced to 0")
	_assert(army_mgr.get_movement_state() == PlayerArmyManagerScript.MovementState.GARRISONED, "TC-COMBAT.10: 0-soldier army safely normalized to GARRISONED")

func _test_combat_serialization_roundtrip() -> void:
	print("\n--- Test 11: Combat Serialization Roundtrip ---")
	var u1 = TacticalUnitScript.new()
	u1.unit_id = "tac_save_1"
	u1.unit_name = "Chiến Binh Thử Nghiệm"
	u1.current_cell = Vector2i(15, 20)
	u1.target_cell = Vector2i(15, 20)
	u1.health = 65.0
	u1.max_health = 120.0
	u1.attack_damage = 35.0
	u1.attack_range = 2
	u1.attack_cooldown = 1.5
	u1.attack_cooldown_remaining = 0.4
	u1.faction_id = "player"

	var data: Dictionary = u1.serialize()
	_assert(float(data.get("health")) == 65.0, "TC-COMBAT.11: Serialized health is 65.0")
	_assert(float(data.get("max_health")) == 120.0, "TC-COMBAT.11: Serialized max_health is 120.0")
	_assert(float(data.get("attack_damage")) == 35.0, "TC-COMBAT.11: Serialized attack_damage is 35.0")
	_assert(int(data.get("attack_range")) == 2, "TC-COMBAT.11: Serialized attack_range is 2")

	var u2 = TacticalUnitScript.new()
	var ok: bool = u2.deserialize(data)
	_assert(ok == true, "TC-COMBAT.11: Deserialization returned true")
	_assert(u2.health == 65.0, "TC-COMBAT.11: Restored health matches 65.0")
	_assert(u2.max_health == 120.0, "TC-COMBAT.11: Restored max_health matches 120.0")
	_assert(u2.attack_damage == 35.0, "TC-COMBAT.11: Restored attack_damage matches 35.0")
	_assert(u2.attack_range == 2, "TC-COMBAT.11: Restored attack_range matches 2")
	_assert(u2.attack_cooldown == 1.5, "TC-COMBAT.11: Restored attack_cooldown matches 1.5")
	_assert(u2.is_alive == true, "TC-COMBAT.11: Restored is_alive matches true")

	u1.free()
	u2.free()
