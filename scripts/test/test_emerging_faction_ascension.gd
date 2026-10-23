extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1P: Emerging Faction Ascension Gates
## Validates authoritative ascension gates for the neutral tribe evolving into an emerging power:
## - TC-EMERGE.1: Happy path ascension (all gates met -> type, name, military, stability updated; signal emitted once; no resource deduction)
## - TC-EMERGE.2: Population gate (population < 45 fails closed)
## - TC-EMERGE.3: Time gate (day < 10 fails closed)
## - TC-EMERGE.4: Resource gate (wood < 60, herbs < 30, or missing keys fails closed)
## - TC-EMERGE.5: Stability gate & boundary analysis (stability < 50.0 fails; stability == 50.0 succeeds)
## - TC-EMERGE.6: Recovery & retry (gate replenishment allows ascension on next simulation day)
## - TC-EMERGE.7: Exactly-once event emission & state idempotency on subsequent daily ticks
## - TC-EMERGE.8: Single emerging power rule (world already possessing emerging_power prevents second ascension)
## - TC-EMERGE.9: Missing faction safety & null resilience
## - TC-EMERGE.10: Integrated SaveManager persistence, schema validation, and reload idempotency
## - TC-EMERGE.11: HUD event banner & diplomacy refresh integration

const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const HUDScene: PackedScene = preload("res://scenes/ui/hud.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1P EMERGING FACTION ASCENSION TESTS")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1P ASCENSION TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1P ASCENSION TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

func _assert_true(cond: bool, test_name: String, msg: String = "") -> void:
	if not cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected true. %s" % [test_name, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_false(cond: bool, test_name: String, msg: String = "") -> void:
	if cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected false. %s" % [test_name, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_eq(actual: Variant, expected: Variant, test_name: String, msg: String = "") -> void:
	if actual != expected:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected %s, got %s. %s" % [test_name, str(expected), str(actual), msg])
	else:
		print("  ✅ PASS [%s]: %s == %s%s" % [test_name, str(actual), str(expected), (" - " + msg) if msg != "" else ""])

func _assert_approx(actual: float, expected: float, test_name: String, tol: float = 0.001) -> void:
	if abs(actual - expected) > tol:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected approx %f, got %f (tol %f)" % [test_name, expected, actual, tol])
	else:
		print("  ✅ PASS [%s]: Approx %f == %f" % [test_name, actual, expected])

func _run_all_tests() -> void:
	test_tc_emerge_1_happy_path()
	test_tc_emerge_2_population_gate()
	test_tc_emerge_3_time_gate()
	test_tc_emerge_4_resource_gate()
	test_tc_emerge_5_stability_gate()
	test_tc_emerge_6_recovery_and_retry()
	test_tc_emerge_7_exactly_once_emission()
	test_tc_emerge_8_single_emerging_power_limit()
	test_tc_emerge_9_missing_faction_safety()
	test_tc_emerge_10_save_load_persistence()
	test_tc_emerge_11_hud_integration()

# -----------------------------------------------------------------------------
# TC-EMERGE.1: Happy Path Ascension
# -----------------------------------------------------------------------------
func test_tc_emerge_1_happy_path() -> void:
	print("\n--- TC-EMERGE.1: Happy Path Ascension ---")
	var fm = FactionManagerScript.new()
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	_assert_true(tribe != null, "TC-EMERGE.1-INIT", "Neutral tribe must exist initially")
	_assert_eq(tribe.type, "neutral_tribe", "TC-EMERGE.1-TYPE-INIT", "Initial type must be neutral_tribe")
	_assert_eq(tribe.name, "Bản Làng Rừng Xanh", "TC-EMERGE.1-NAME-INIT", "Initial name must be Bản Làng Rừng Xanh")

	# Set conditions to satisfy all gates: pop = 44 (becomes 45 on daily tick), day = 10, wood = 120, herbs = 60, stab = 70.0
	tribe.population = 44
	var wood_before: int = tribe.resources.get(EconomyConfigScript.RES_WOOD, 0)
	var herbs_before: int = tribe.resources.get(EconomyConfigScript.RES_HERBS, 0)

	var emissions: Array = []
	fm.emerging_faction_ascended.connect(func(fac_id: String, new_name: String):
		emissions.append({"id": fac_id, "name": new_name})
	)

	fm.update_daily_simulation(10)

	_assert_eq(emissions.size(), 1, "TC-EMERGE.1-SIGNAL", "emerging_faction_ascended signal emitted exactly once")
	if not emissions.is_empty():
		_assert_eq(emissions[0]["id"], "neutral_tribe", "TC-EMERGE.1-SIG-ID", "Signal emitted faction_id matches")
		_assert_eq(emissions[0]["name"], FactionManagerScript.ASCENSION_NEW_NAME, "TC-EMERGE.1-SIG-NAME", "Signal emitted new_name matches")
	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.1-TYPE", "Faction type evolved to emerging_power")
	_assert_eq(tribe.name, FactionManagerScript.ASCENSION_NEW_NAME, "TC-EMERGE.1-NAME", "Faction name evolved to Liên Minh Rừng Thiêng")
	_assert_approx(tribe.military_power, FactionManagerScript.ASCENSION_NEW_MILITARY_POWER, "TC-EMERGE.1-MIL", 0.01)
	_assert_approx(tribe.stability, FactionManagerScript.ASCENSION_NEW_STABILITY, "TC-EMERGE.1-STAB", 0.01)
	_assert_eq(tribe.population, 45, "TC-EMERGE.1-POP", "Population incremented to 45")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_WOOD, 0), wood_before, "TC-EMERGE.1-WOOD-NO-CONSUME", "Wood not consumed on ascension")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_HERBS, 0), herbs_before, "TC-EMERGE.1-HERBS-NO-CONSUME", "Herbs not consumed on ascension")

# -----------------------------------------------------------------------------
# TC-EMERGE.2: Population Gate
# -----------------------------------------------------------------------------
func test_tc_emerge_2_population_gate() -> void:
	print("\n--- TC-EMERGE.2: Population Gate ---")
	var fm = FactionManagerScript.new()
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	# pop = 40 (becomes 41 on daily tick < 45)
	tribe.population = 40

	var emissions: Array = []
	fm.emerging_faction_ascended.connect(func(fac_id, new_name):
		emissions.append({"id": fac_id, "name": new_name})
	)

	_assert_false(fm.can_emerging_faction_ascend(10), "TC-EMERGE.2-CAN-PRE", "can_emerging_faction_ascend returns false when pop < 45")
	fm.update_daily_simulation(10)

	_assert_eq(emissions.size(), 0, "TC-EMERGE.2-NO-SIGNAL", "No ascension signal when pop < 45")
	_assert_eq(tribe.type, "neutral_tribe", "TC-EMERGE.2-TYPE", "Type remains neutral_tribe")
	_assert_eq(tribe.name, "Bản Làng Rừng Xanh", "TC-EMERGE.2-NAME", "Name remains Bản Làng Rừng Xanh")
	_assert_approx(tribe.military_power, 30.0, "TC-EMERGE.2-MIL", 0.01)
	_assert_eq(tribe.population, 41, "TC-EMERGE.2-POP", "Population incremented to 41")

# -----------------------------------------------------------------------------
# TC-EMERGE.3: Time Gate
# -----------------------------------------------------------------------------
func test_tc_emerge_3_time_gate() -> void:
	print("\n--- TC-EMERGE.3: Time Gate ---")
	var fm = FactionManagerScript.new()
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44 # Will become 45 on daily tick

	var emissions: Array = []
	fm.emerging_faction_ascended.connect(func(fac_id, new_name):
		emissions.append({"id": fac_id, "name": new_name})
	)

	# Day 9 < 10
	_assert_false(fm.can_emerging_faction_ascend(9), "TC-EMERGE.3-CAN-PRE", "can_emerging_faction_ascend returns false on Day 9")
	fm.update_daily_simulation(9)

	_assert_eq(emissions.size(), 0, "TC-EMERGE.3-NO-SIGNAL", "No ascension signal on Day 9")
	_assert_eq(tribe.type, "neutral_tribe", "TC-EMERGE.3-TYPE", "Type remains neutral_tribe")
	_assert_eq(tribe.population, 45, "TC-EMERGE.3-POP", "Population incremented to 45")

	# On Day 10 with pop 45, check that can_emerging_faction_ascend is true
	_assert_true(fm.can_emerging_faction_ascend(10), "TC-EMERGE.3-CAN-POST", "can_emerging_faction_ascend returns true on Day 10 with pop 45")

# -----------------------------------------------------------------------------
# TC-EMERGE.4: Resource Gate
# -----------------------------------------------------------------------------
func test_tc_emerge_4_resource_gate() -> void:
	print("\n--- TC-EMERGE.4: Resource Gate ---")

	# Sub-case A: Wood < 60 (wood = 59, herbs = 30)
	var fmA = FactionManagerScript.new()
	var tribeA: FactionData = fmA.get_faction("neutral_tribe")
	tribeA.population = 44
	tribeA.resources = {EconomyConfigScript.RES_WOOD: 59, EconomyConfigScript.RES_HERBS: 30}
	var emissionsA: Array = []
	fmA.emerging_faction_ascended.connect(func(fac_id, new_name): emissionsA.append({"id": fac_id, "name": new_name}))

	_assert_false(fmA.can_emerging_faction_ascend(10), "TC-EMERGE.4-CAN-WOOD-DEFICIT", "Fails when wood is 59 < 60")
	fmA.update_daily_simulation(10)
	_assert_eq(emissionsA.size(), 0, "TC-EMERGE.4-NO-SIG-WOOD", "No ascension when wood < 60")
	_assert_eq(tribeA.type, "neutral_tribe", "TC-EMERGE.4-TYPE-WOOD", "Type unchanged when wood deficient")

	# Sub-case B: Herbs < 30 (wood = 60, herbs = 29)
	var fmB = FactionManagerScript.new()
	var tribeB: FactionData = fmB.get_faction("neutral_tribe")
	tribeB.population = 44
	tribeB.resources = {EconomyConfigScript.RES_WOOD: 60, EconomyConfigScript.RES_HERBS: 29}
	var emissionsB: Array = []
	fmB.emerging_faction_ascended.connect(func(fac_id, new_name): emissionsB.append({"id": fac_id, "name": new_name}))

	_assert_false(fmB.can_emerging_faction_ascend(10), "TC-EMERGE.4-CAN-HERB-DEFICIT", "Fails when herbs is 29 < 30")
	fmB.update_daily_simulation(10)
	_assert_eq(emissionsB.size(), 0, "TC-EMERGE.4-NO-SIG-HERB", "No ascension when herbs < 30")
	_assert_eq(tribeB.type, "neutral_tribe", "TC-EMERGE.4-TYPE-HERB", "Type unchanged when herbs deficient")

	# Sub-case C: Missing resource dictionary keys
	var fmC = FactionManagerScript.new()
	var tribeC: FactionData = fmC.get_faction("neutral_tribe")
	tribeC.population = 44
	tribeC.resources = {}
	var emissionsC: Array = []
	fmC.emerging_faction_ascended.connect(func(fac_id, new_name): emissionsC.append({"id": fac_id, "name": new_name}))

	_assert_false(fmC.can_emerging_faction_ascend(10), "TC-EMERGE.4-CAN-EMPTY-RES", "Fails when resources dictionary is empty")
	fmC.update_daily_simulation(10)
	_assert_eq(emissionsC.size(), 0, "TC-EMERGE.4-NO-SIG-EMPTY", "No ascension when resources empty")

# -----------------------------------------------------------------------------
# TC-EMERGE.5: Stability Gate & Boundary Analysis
# -----------------------------------------------------------------------------
func test_tc_emerge_5_stability_gate() -> void:
	print("\n--- TC-EMERGE.5: Stability Gate & Boundary Analysis ---")

	# Sub-case A: Stability below 50.0 (49.9)
	var fmA = FactionManagerScript.new()
	var tribeA: FactionData = fmA.get_faction("neutral_tribe")
	tribeA.population = 44
	tribeA.stability = 49.9
	var emissionsA: Array = []
	fmA.emerging_faction_ascended.connect(func(fac_id, new_name): emissionsA.append({"id": fac_id, "name": new_name}))

	_assert_false(fmA.can_emerging_faction_ascend(10), "TC-EMERGE.5-CAN-BELOW-50", "Fails when stability is 49.9 < 50.0")
	fmA.update_daily_simulation(10)
	_assert_eq(emissionsA.size(), 0, "TC-EMERGE.5-NO-SIG-BELOW", "No ascension when stability < 50.0")
	_assert_eq(tribeA.type, "neutral_tribe", "TC-EMERGE.5-TYPE-BELOW", "Type unchanged when stability < 50.0")

	# Sub-case B: Stability exactly 50.0 (exact boundary)
	var fmB = FactionManagerScript.new()
	var tribeB: FactionData = fmB.get_faction("neutral_tribe")
	tribeB.population = 45 # Satisfies population condition directly
	tribeB.stability = 50.0
	var emissionsB: Array = []
	fmB.emerging_faction_ascended.connect(func(fac_id, new_name): emissionsB.append({"id": fac_id, "name": new_name}))

	_assert_true(fmB.can_emerging_faction_ascend(10), "TC-EMERGE.5-CAN-EXACT-50", "Succeeds when stability is exactly 50.0")
	fmB.update_daily_simulation(10)
	_assert_eq(emissionsB.size(), 1, "TC-EMERGE.5-SIG-EXACT-50", "Ascension triggered when stability == 50.0")
	_assert_eq(tribeB.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.5-TYPE-ASCENDED", "Evolved to emerging_power")

# -----------------------------------------------------------------------------
# TC-EMERGE.6: Recovery and Retry on Next Valid Day
# -----------------------------------------------------------------------------
func test_tc_emerge_6_recovery_and_retry() -> void:
	print("\n--- TC-EMERGE.6: Recovery and Retry ---")
	var fm = FactionManagerScript.new()
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44
	# Initial deficit on Day 10: herbs = 20 < 30
	tribe.resources = {EconomyConfigScript.RES_WOOD: 80, EconomyConfigScript.RES_HERBS: 20}

	var emissions: Array = []
	fm.emerging_faction_ascended.connect(func(fac_id, new_name): emissions.append({"id": fac_id, "name": new_name}))

	# Day 10 tick
	fm.update_daily_simulation(10)
	_assert_eq(emissions.size(), 0, "TC-EMERGE.6-DAY10-BLOCKED", "Day 10 blocked due to herb deficit")
	_assert_eq(tribe.type, "neutral_tribe", "TC-EMERGE.6-DAY10-TYPE", "Type remains neutral_tribe")
	_assert_eq(tribe.population, 45, "TC-EMERGE.6-DAY10-POP", "Pop incremented to 45")

	# Tribe replenishes herbs before Day 11
	tribe.resources[EconomyConfigScript.RES_HERBS] = 35
	_assert_true(fm.can_emerging_faction_ascend(11), "TC-EMERGE.6-CAN-DAY11", "can_emerging_faction_ascend becomes true after herbs replenished")

	# Day 11 tick
	fm.update_daily_simulation(11)
	_assert_eq(emissions.size(), 1, "TC-EMERGE.6-DAY11-ASCENDED", "Day 11 successfully triggered ascension")
	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.6-DAY11-TYPE", "Type became emerging_power")
	_assert_eq(tribe.name, FactionManagerScript.ASCENSION_NEW_NAME, "TC-EMERGE.6-DAY11-NAME", "Name became Liên Minh Rừng Thiêng")

# -----------------------------------------------------------------------------
# TC-EMERGE.7: Exactly-Once Event Emission & Idempotency
# -----------------------------------------------------------------------------
func test_tc_emerge_7_exactly_once_emission() -> void:
	print("\n--- TC-EMERGE.7: Exactly-Once Emission & Idempotency ---")
	var fm = FactionManagerScript.new()
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44

	var emissions: Array = []
	fm.emerging_faction_ascended.connect(func(fac_id, new_name): emissions.append({"id": fac_id, "name": new_name}))

	# Day 10: ascendance occurs
	fm.update_daily_simulation(10)
	_assert_eq(emissions.size(), 1, "TC-EMERGE.7-DAY10", "Signal emitted exactly once on Day 10")
	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.7-TYPE-D10", "Type is emerging_power")

	# Day 11, 12, 13: subsequent daily simulation ticks (Package 1S executes power_consolidation: +4.0 mil/day, +2.0 stab/day up to 95.0)
	fm.update_daily_simulation(11)
	fm.update_daily_simulation(12)
	fm.update_daily_simulation(13)

	_assert_eq(emissions.size(), 1, "TC-EMERGE.7-SUBSEQUENT", "Signal never re-emitted on subsequent days")
	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.7-TYPE-STABLE", "Type remains emerging_power")
	_assert_eq(tribe.name, FactionManagerScript.ASCENSION_NEW_NAME, "TC-EMERGE.7-NAME-STABLE", "Name remains Liên Minh Rừng Thiêng")
	_assert_approx(tribe.military_power, FactionManagerScript.ASCENSION_NEW_MILITARY_POWER + 12.0, "TC-EMERGE.7-MIL-STABLE", 0.01)
	_assert_approx(tribe.stability, FactionManagerScript.ASCENSION_NEW_STABILITY + 6.0, "TC-EMERGE.7-STAB-STABLE", 0.01)

# -----------------------------------------------------------------------------
# TC-EMERGE.8: Single Emerging Power Rule
# -----------------------------------------------------------------------------
func test_tc_emerge_8_single_emerging_power_limit() -> void:
	print("\n--- TC-EMERGE.8: Single Emerging Power Rule ---")
	var fm = FactionManagerScript.new()

	_assert_false(fm.has_emerging_power(), "TC-EMERGE.8-HAS-PRE", "Initially no emerging power exists")

	# Suppose a rival has type "emerging_power"
	var rival = fm.get_faction("rival_military")
	rival.type = "emerging_power"

	_assert_true(fm.has_emerging_power(), "TC-EMERGE.8-HAS-POST", "has_emerging_power returns true when rival is emerging_power")

	# Neutral tribe satisfies all gates
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 50

	_assert_false(fm.can_emerging_faction_ascend(10), "TC-EMERGE.8-CAN-BLOCKED", "can_emerging_faction_ascend blocked by existing emerging power")

	var emissions: Array = []
	fm.emerging_faction_ascended.connect(func(fac_id, new_name): emissions.append({"id": fac_id, "name": new_name}))
	fm.update_daily_simulation(10)

	_assert_eq(emissions.size(), 0, "TC-EMERGE.8-NO-SIGNAL", "No ascension signal when emerging power already exists")
	_assert_eq(tribe.type, "neutral_tribe", "TC-EMERGE.8-TYPE", "Type remains neutral_tribe")

# -----------------------------------------------------------------------------
# TC-EMERGE.9: Missing Faction Safety & Null Resilience
# -----------------------------------------------------------------------------
func test_tc_emerge_9_missing_faction_safety() -> void:
	print("\n--- TC-EMERGE.9: Missing Faction Safety ---")
	var fm = FactionManagerScript.new()
	fm._factions.erase("neutral_tribe")

	_assert_true(fm.get_faction("neutral_tribe") == null, "TC-EMERGE.9-NULL", "neutral_tribe removed")
	_assert_false(fm.can_emerging_faction_ascend(10), "TC-EMERGE.9-CAN-NULL", "can_emerging_faction_ascend fails gracefully on null tribe")

	var rival_mil: FactionData = fm.get_faction("rival_military")
	var rival_merch: FactionData = fm.get_faction("rival_merchant")
	_assert_true(rival_mil != null and rival_merch != null, "TC-EMERGE.9-RIVALS-EXIST", "Unrelated rival factions exist")

	var emissions: Array = []
	var on_ascended := func(fac_id: String, new_name: String):
		emissions.append({"id": fac_id, "name": new_name})
	fm.emerging_faction_ascended.connect(on_ascended)

	# Execute daily update without neutral tribe present
	fm.update_daily_simulation(10)

	_assert_true(fm.get_faction("neutral_tribe") == null, "TC-EMERGE.9-STILL-NULL", "neutral_tribe remains absent after simulation tick")
	_assert_eq(emissions.size(), 0, "TC-EMERGE.9-NO-SIGNAL", "Zero emerging_faction_ascended signals emitted when neutral tribe is absent")
	_assert_eq(rival_mil.population, 60, "TC-EMERGE.9-MIL-POP-INTACT", "Rival military population unmutated")
	_assert_approx(rival_mil.military_power, 80.0, "TC-EMERGE.9-MIL-PWR-INTACT", 0.01)
	_assert_eq(rival_mil.type, "rival_military", "TC-EMERGE.9-MIL-TYPE-INTACT", "Rival military type unmutated")
	_assert_eq(rival_merch.population, 50, "TC-EMERGE.9-MERCH-POP-INTACT", "Rival merchant population unmutated")
	_assert_approx(rival_merch.military_power, 50.0, "TC-EMERGE.9-MERCH-PWR-INTACT", 0.01)
	_assert_eq(rival_merch.type, "rival_merchant", "TC-EMERGE.9-MERCH-TYPE-INTACT", "Rival merchant type unmutated")
	_assert_false(fm.has_emerging_power(), "TC-EMERGE.9-NO-EMERGING-POWER", "World still has zero emerging powers")

	if fm.emerging_faction_ascended.is_connected(on_ascended):
		fm.emerging_faction_ascended.disconnect(on_ascended)

# -----------------------------------------------------------------------------
# TC-EMERGE.10: Integrated SaveManager Persistence & Reload Idempotency
# -----------------------------------------------------------------------------
func test_tc_emerge_10_save_load_persistence() -> void:
	print("\n--- TC-EMERGE.10: Save/Load Persistence & Idempotency ---")
	_assert_true(world_instance != null, "TC-EMERGE.10-WORLD", "WorldView live instance exists")
	var fm: FactionManager = world_instance.get("faction_mgr")
	_assert_true(fm != null, "TC-EMERGE.10-FM", "FactionManager exists on world instance")

	# Ascend the neutral tribe on the live world instance
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44
	tribe.resources = {EconomyConfigScript.RES_WOOD: 125, EconomyConfigScript.RES_HERBS: 65}
	fm.update_daily_simulation(10)

	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.10-LIVE-ASCENDED", "Live neutral_tribe ascended")
	_assert_eq(tribe.name, FactionManagerScript.ASCENSION_NEW_NAME, "TC-EMERGE.10-LIVE-NAME", "Live name is Liên Minh Rừng Thiêng")

	# 1. Serialize world state
	var saved_data: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	_assert_true(saved_data.has("factions"), "TC-EMERGE.10-HAS-FACTIONS", "Serialized data contains factions")

	var fac_dict: Dictionary = saved_data["factions"].get("factions", {})
	_assert_true(fac_dict.has("neutral_tribe"), "TC-EMERGE.10-HAS-TRIBE", "Serialized factions contains neutral_tribe")

	var tribe_saved: Dictionary = fac_dict["neutral_tribe"]
	_assert_eq(tribe_saved.get("name"), FactionManagerScript.ASCENSION_NEW_NAME, "TC-EMERGE.10-SAVED-NAME", "Saved name is Liên Minh Rừng Thiêng")
	_assert_eq(tribe_saved.get("type"), FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.10-SAVED-TYPE", "Saved type is emerging_power")
	_assert_approx(float(tribe_saved.get("military_power", 0.0)), 55.0, "TC-EMERGE.10-SAVED-MIL", 0.01)
	_assert_approx(float(tribe_saved.get("stability", 0.0)), 85.0, "TC-EMERGE.10-SAVED-STAB", 0.01)
	_assert_true(tribe_saved.has("resources"), "TC-EMERGE.10-SAVED-RES", "Saved faction dictionary has resources")
	_assert_eq(int(tribe_saved["resources"].get(EconomyConfigScript.RES_WOOD, 0)), 125, "TC-EMERGE.10-SAVED-WOOD", "Saved wood matches")
	_assert_eq(int(tribe_saved["resources"].get(EconomyConfigScript.RES_HERBS, 0)), 65, "TC-EMERGE.10-SAVED-HERBS", "Saved herbs matches")

	# 2. Validate save schema
	var val_res: Dictionary = SaveManagerScript.validate_save_data(saved_data)
	_assert_true(val_res.get("valid", false), "TC-EMERGE.10-SCHEMA-VALID", "Schema validation passes: " + str(val_res.get("error", "")))

	# 3. Mutate live world state to simulate reset / stale state
	tribe.name = "Bản Làng Reset"
	tribe.type = "neutral_tribe"
	tribe.military_power = 20.0
	tribe.stability = 30.0
	tribe.resources = {EconomyConfigScript.RES_WOOD: 10, EconomyConfigScript.RES_HERBS: 5}

	# 4. Attach emission spy BEFORE the first load to observe load-time signal behavior
	var load_emissions: Array = []
	var on_ascended := func(fac_id: String, new_name: String):
		load_emissions.append({"id": fac_id, "name": new_name})
	fm.emerging_faction_ascended.connect(on_ascended)

	# 5. Apply loaded state to world
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_res.get("success", false), "TC-EMERGE.10-APPLY-SUCCESS", "apply_loaded_state_to_world succeeded")
	_assert_eq(load_emissions.size(), 0, "TC-EMERGE.10-LOAD1-NO-SIGNAL", "Zero emerging_faction_ascended signals emitted during first world load")

	# 6. Verify restored state
	var restored_tribe: FactionData = fm.get_faction("neutral_tribe")
	_assert_eq(restored_tribe.name, FactionManagerScript.ASCENSION_NEW_NAME, "TC-EMERGE.10-REST-NAME", "Restored name matches")
	_assert_eq(restored_tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.10-REST-TYPE", "Restored type matches")
	_assert_approx(restored_tribe.military_power, 55.0, "TC-EMERGE.10-REST-MIL", 0.01)
	_assert_approx(restored_tribe.stability, 85.0, "TC-EMERGE.10-REST-STAB", 0.01)
	_assert_eq(restored_tribe.resources.get(EconomyConfigScript.RES_WOOD, 0), 125, "TC-EMERGE.10-REST-WOOD", "Restored wood matches")
	_assert_eq(restored_tribe.resources.get(EconomyConfigScript.RES_HERBS, 0), 65, "TC-EMERGE.10-REST-HERBS", "Restored herbs matches")

	# 7. Subsequent daily tick on restored world does NOT re-ascend
	fm.update_daily_simulation(11)
	_assert_eq(load_emissions.size(), 0, "TC-EMERGE.10-NO-RETRIGGER", "Daily simulation tick on restored world does not re-trigger ascension")

	# 8. Double-load idempotency & signal silence
	var apply_res2: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_res2.get("success", false), "TC-EMERGE.10-DOUBLE-LOAD-OK", "Second load application succeeded")
	_assert_eq(load_emissions.size(), 0, "TC-EMERGE.10-LOAD2-NO-SIGNAL", "Zero emerging_faction_ascended signals emitted during second world load")
	_assert_eq(restored_tribe.name, FactionManagerScript.ASCENSION_NEW_NAME, "TC-EMERGE.10-DOUBLE-NAME", "Name remains intact after double-load")
	_assert_eq(restored_tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.10-DOUBLE-TYPE", "Type remains intact after double-load")

	if fm.emerging_faction_ascended.is_connected(on_ascended):
		fm.emerging_faction_ascended.disconnect(on_ascended)

# -----------------------------------------------------------------------------
# TC-EMERGE.11: HUD Signal Connection & Event Banner Integration
# -----------------------------------------------------------------------------
func _find_faction_card_title(factions_vbox: VBoxContainer, faction_name: String) -> bool:
	if factions_vbox == null:
		return false
	for child in factions_vbox.get_children():
		if child.is_queued_for_deletion():
			continue
		for sub in child.get_children():
			if sub is VBoxContainer:
				for elem in sub.get_children():
					if elem is Label and elem.text.contains(faction_name):
						return true
	return false

func test_tc_emerge_11_hud_integration() -> void:
	print("\n--- TC-EMERGE.11: HUD Integration ---")
	var hud = HUDScene.instantiate()
	root.add_child(hud)

	var fm = FactionManagerScript.new()
	hud.set_faction_manager(fm, world_instance)

	# Initial diplomacy UI refresh to display starter factions
	hud.call("_refresh_diplomacy_ui")
	_assert_true(_find_faction_card_title(hud.factions_list_vbox, "Bản Làng Rừng Xanh"), "TC-EMERGE.11-PRE-CARD-EXISTS", "Initial diplomacy UI renders Bản Làng Rừng Xanh card")
	_assert_false(_find_faction_card_title(hud.factions_list_vbox, FactionManagerScript.ASCENSION_NEW_NAME), "TC-EMERGE.11-PRE-NO-ASCENDED", "Initial diplomacy UI does not show Liên Minh Rừng Thiêng")

	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44
	tribe.resources = {EconomyConfigScript.RES_WOOD: 120, EconomyConfigScript.RES_HERBS: 60}
	tribe.stability = 70.0

	# Trigger ascension on Day 10
	fm.update_daily_simulation(10)

	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-EMERGE.11-ASCENDED", "Tribe ascended to emerging_power")
	_assert_true(hud.event_banner != null, "TC-EMERGE.11-BANNER-EXISTS", "HUD event banner exists")
	_assert_true(hud.event_banner.visible, "TC-EMERGE.11-BANNER-VISIBLE", "HUD event banner displayed upon ascension")
	_assert_true(hud.event_title.text.contains("Thế Lực Mới Nổi"), "TC-EMERGE.11-BANNER-TITLE", "Event banner title correct: " + hud.event_title.text)
	_assert_true(hud.event_desc.text.contains(FactionManagerScript.ASCENSION_NEW_NAME), "TC-EMERGE.11-BANNER-DESC", "Event banner description mentions " + FactionManagerScript.ASCENSION_NEW_NAME)

	# Assert that _refresh_diplomacy_ui() was called by signal handler and updated rendered cards
	_assert_true(_find_faction_card_title(hud.factions_list_vbox, FactionManagerScript.ASCENSION_NEW_NAME), "TC-EMERGE.11-CARD-REFRESHED", "Refreshed diplomacy UI contains newly ascended card 'Liên Minh Rừng Thiêng'")
	_assert_false(_find_faction_card_title(hud.factions_list_vbox, "Bản Làng Rừng Xanh"), "TC-EMERGE.11-CARD-OLD-REMOVED", "Refreshed diplomacy UI no longer displays 'Bản Làng Rừng Xanh'")

	hud.queue_free()
