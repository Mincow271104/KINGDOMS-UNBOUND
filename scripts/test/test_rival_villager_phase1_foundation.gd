extends SceneTree
## Focused Phase 1 Test Suite: Rival Settlement Villager System — Core Data Foundation & Isolation
## Covers Section 7.1 (SettlementVillagerData), 7.2 (Settlement Isolation),
## 7.3 (ID Allocator), and 7.4 (Architectural Isolation & FactionData.population invariance),
## plus Phase 1 Hardening edge cases (Reviews A–E).

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementJobBoardScript = preload("res://scripts/world/settlement_job_board.gd")
const SettlementWorkplaceRegistryScript = preload("res://scripts/world/settlement_workplace_registry.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Rival Settlement Villager Phase 1 Foundation")
	print("========================================================")

	_test_7_1_villager_data_model()
	_test_7_2_settlement_isolation()
	_test_7_3_id_allocator()
	_test_7_4_architectural_isolation()
	_test_7_5_external_id_insertion_and_getter_ownership()
	_test_7_6_identity_and_ownership_immutability()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_7_1_villager_data_model() -> void:
	print("\n[7.1] SettlementVillagerData Integrity, Defaults, No-Alias & Serialization")
	var v1 := SettlementVillagerDataScript.new(
		"npc_stl_rival_military_1",
		"stl_rival_military",
		"rival_military",
		"Trần Văn Hùng",
		"guard",
		Vector2i(20, 40)
	)
	_assert(v1.is_valid(), "Valid villager passes is_valid()")
	_assert(v1.villager_id == "npc_stl_rival_military_1", "villager_id stored")
	_assert(v1.settlement_id == "stl_rival_military", "settlement_id stored")
	_assert(v1.home_settlement_id == "stl_rival_military", "home_settlement_id defaults to settlement_id")
	_assert(v1.origin_faction_id == "rival_military", "origin_faction_id stored")
	_assert(v1.current_faction_id == "rival_military", "current_faction_id defaults to origin_faction_id")
	_assert(v1.life_state == "alive" and v1.task_state == "idle" and v1.rest_phase == "none", "Default lifecycle/task/rest states")
	_assert(is_equal_approx(v1.hunger, 10.0) and is_equal_approx(v1.fatigue, 10.0) and is_equal_approx(v1.health, 100.0) and is_equal_approx(v1.morale, 70.0), "Default needs")
	_assert(v1.last_processed_hour_seq == 0, "Default last_processed_hour_seq == 0")

	# Verify two villagers never share mutable cargo or skills Dictionaries
	var v2 := SettlementVillagerDataScript.new(
		"npc_stl_rival_military_2",
		"stl_rival_military",
		"rival_military",
		"Lê Thị Mai",
		"hauler",
		Vector2i(21, 40)
	)
	v1.set_cargo("food", 8, "mil_store", Vector2i(22, 40))
	v1.skills["hauling"] = 120.0
	_assert(v2.get_carrying_amount() == 0 and v2.get_carrying_resource() == "", "v2 cargo isolated from v1 cargo mutation")
	_assert(is_equal_approx(float(v2.skills["hauling"]), 0.0), "v2 skills isolated from v1 skills mutation")

	# Serialization / deserialization round-trip & no-alias (both to_dict and from_dict)
	v1.last_processed_hour_seq = 18
	v1.work_hours_done = 1.5
	var d1: Dictionary = v1.to_dict()
	d1["cargo"]["amount"] = 999
	d1["skills"]["hauling"] = 999.0
	_assert(v1.get_carrying_amount() == 8 and is_equal_approx(float(v1.skills["hauling"]), 120.0), "to_dict() returns deep copy isolated from live cargo & skills")

	var input_dict: Dictionary = v1.to_dict()
	var v1_restored := SettlementVillagerDataScript.from_dict(input_dict)
	input_dict["cargo"]["amount"] = 777
	input_dict["skills"]["hauling"] = 777.0
	_assert(v1_restored != null and v1_restored.is_valid(), "from_dict() restores valid villager")
	_assert(v1_restored.get_carrying_amount() == 8 and is_equal_approx(float(v1_restored.skills["hauling"]), 120.0), "from_dict() does not retain shared references to caller input dict")
	_assert(v1_restored.villager_id == v1.villager_id and v1_restored.cell == Vector2i(20, 40), "Round-trip preserves ID and cell")
	_assert(v1_restored.get_carrying_resource() == "food" and v1_restored.get_carrying_amount() == 8, "Round-trip preserves cargo")
	_assert(v1_restored.last_processed_hour_seq == 18 and is_equal_approx(v1_restored.work_hours_done, 1.5), "Round-trip preserves hour_seq and work_hours_done")
	_assert(v1_restored.to_dict() == v1.to_dict(), "Deterministic to_dict() equality across round-trip")

	# Missing optional fields restored safely
	var minimal_dict := {
		"villager_id": "npc_stl_neutral_tribe_1",
		"settlement_id": "stl_neutral_tribe",
		"origin_faction_id": "neutral_tribe"
	}
	var v_min := SettlementVillagerDataScript.from_dict(minimal_dict)
	_assert(v_min != null and v_min.is_valid(), "Minimal dict with missing optional fields restores safely")
	_assert(v_min.role == "idle" and v_min.life_state == "alive" and v_min.get_carrying_amount() == 0, "Missing optional fields receive safe defaults")

	# Invalid / malformed inputs rejected
	_assert(SettlementVillagerDataScript.from_dict(null) == null, "Null input rejected")
	_assert(SettlementVillagerDataScript.from_dict("invalid") == null, "Non-dict input rejected")
	_assert(SettlementVillagerDataScript.from_dict({}) == null, "Empty dict rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "", "settlement_id": "stl_a", "origin_faction_id": "rival_military"}) == null, "Empty villager_id rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "npc_stl_b_1", "settlement_id": "stl_a", "origin_faction_id": "rival_military"}) == null, "Mismatched ID prefix vs settlement_id rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "npc_stl_a_1", "settlement_id": "stl_a", "origin_faction_id": "rival_military", "role": "invalid_role"}) == null, "Unknown role rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "npc_stl_a_1", "settlement_id": "stl_a", "origin_faction_id": "rival_military", "hunger": "bad_type"}) == null, "Malformed need type rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "npc_stl_a_1", "settlement_id": "stl_a", "origin_faction_id": "rival_military", "hunger": 150.0}) == null, "Out-of-range need (>100) rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "npc_stl_a_1", "settlement_id": "stl_a", "origin_faction_id": "rival_military", "work_hours_done": -1.0}) == null, "Negative work_hours_done rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "npc_stl_a_1", "settlement_id": "stl_a", "origin_faction_id": "rival_military", "cargo": "not_a_dict"}) == null, "Non-dict cargo rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "npc_stl_a_1", "settlement_id": "stl_a", "origin_faction_id": "rival_military", "cargo": {"resource": "", "amount": 5}}) == null, "Cargo with amount > 0 but empty resource rejected")
	_assert(SettlementVillagerDataScript.from_dict({"villager_id": "npc_stl_a_1", "settlement_id": "stl_a", "origin_faction_id": "rival_military", "skills": {"unknown_vocation": 10.0}}) == null, "Unknown skill vocation rejected")

func _test_7_2_settlement_isolation() -> void:
	print("\n[7.2] Settlement Context, JobBoard & WorkplaceRegistry Isolation")
	var ctx_a := SettlementVillagerContextScript.new("stl_rival_military", "rival_military")
	var ctx_b := SettlementVillagerContextScript.new("stl_rival_merchant", "rival_merchant")

	var va := ctx_a.create_and_add_villager("Vệ Binh A", "guard", Vector2i(10, 10))
	var vb := ctx_b.create_and_add_villager("Thương Nhân B", "hauler", Vector2i(50, 50))

	_assert(va != null and ctx_a.get_villager(va.villager_id) == va, "Settlement A adds & retrieves its own villager")
	_assert(vb != null and ctx_b.get_villager(vb.villager_id) == vb, "Settlement B adds & retrieves its own villager")
	_assert(ctx_a.get_villager(vb.villager_id) == null, "Settlement A cannot retrieve Settlement B's villager")
	_assert(ctx_b.get_villager(va.villager_id) == null, "Settlement B cannot retrieve Settlement A's villager")

	# Reject cross-settlement insertion
	_assert(not ctx_b.add_villager(va), "Villager from Settlement A rejected by Settlement B")
	_assert(ctx_b.get_villager_count() == 1, "Settlement B count unchanged after rejected cross-settlement insert")

	# Reject duplicate ID insertion
	var dup_va := SettlementVillagerDataScript.new(va.villager_id, "stl_rival_military", "rival_military", "Dup", "idle")
	_assert(not ctx_a.add_villager(dup_va), "Duplicate villager_id rejected by Settlement A")
	_assert(ctx_a.get_villager(va.villager_id).villager_name == "Vệ Binh A", "Existing villager not overwritten by duplicate")

	# Removing from A does not affect B
	var va2 := ctx_a.create_and_add_villager("Vệ Binh A2", "idle", Vector2i(11, 10))
	_assert(ctx_a.remove_villager(va.villager_id), "Remove villager from A succeeds")
	_assert(not ctx_a.has_villager(va.villager_id) and ctx_a.has_villager(va2.villager_id), "Removed villager absent from A, remaining villager intact")
	_assert(ctx_b.has_villager(vb.villager_id) and ctx_b.get_villager_count() == 1, "Removing from A does not affect B")

	# Job-board isolation & validation
	var job_a = ctx_a.job_board.create_job_record("guard", "mil_hq", Vector2i(10, 10))
	var job_b = ctx_b.job_board.create_job_record("hauler", "mer_store_1", Vector2i(50, 50))
	_assert(job_a != null and job_b != null, "Both settlement job boards create local job records")
	_assert(ctx_a.job_board.has_job(job_a.job_id) and not ctx_a.job_board.has_job(job_b.job_id), "JobBoard A isolated from JobBoard B")
	_assert(not ctx_b.job_board.register_job(job_a), "JobBoard B rejects job record belonging to Settlement A")
	_assert(SettlementJobBoardScript.from_dict({"settlement_id": "stl_rival_military", "jobs": "not_an_array"}) == null, "JobBoard rejects non-array jobs field")
	_assert(SettlementJobBoardScript.NpcJobRecord.from_dict({"job_id": "npc_job_stl_a_1", "settlement_id": "stl_a", "job_type": "guard", "priority": 99}) == null, "NpcJobRecord rejects out-of-range priority")

	# Workplace-registry isolation & validation
	var wp_a = ctx_a.workplace_registry.register_workplace("mil_hq", "barracks", Vector2i(9, 9), Vector2i(3, 3), Vector2i(10, 12), "", 0, 2, true)
	var wp_b = ctx_b.workplace_registry.register_workplace("mer_store_1", "storehouse", Vector2i(48, 48), Vector2i(2, 2), Vector2i(48, 50), "", 50, 2, true)
	_assert(wp_a != null and wp_b != null, "Both workplace registries register local workplaces")
	_assert(ctx_a.workplace_registry.has_workplace("mil_hq") and not ctx_a.workplace_registry.has_workplace("mer_store_1"), "WorkplaceRegistry A isolated from B")
	_assert(not ctx_b.workplace_registry.register_workplace_record(wp_a), "WorkplaceRegistry B rejects workplace record from Settlement A")
	_assert(SettlementWorkplaceRegistryScript.from_dict({"settlement_id": "stl_rival_military", "workplaces": 123}) == null, "WorkplaceRegistry rejects non-array workplaces field")
	_assert(SettlementWorkplaceRegistryScript.NpcWorkplaceRecord.from_dict({"workplace_id": "wp_1", "settlement_id": "stl_a", "building_type": "farm", "buffer_capacity": 50, "buffer_amount": 99}) == null, "NpcWorkplaceRecord rejects buffer_amount > buffer_capacity")

	# Context serialization round-trip & malformed rejection
	var ctx_a_restored := SettlementVillagerContextScript.from_dict(ctx_a.to_dict())
	_assert(ctx_a_restored != null and ctx_a_restored.get_villager_count() == 1 and ctx_a_restored.has_villager(va2.villager_id), "Context round-trip preserves active villagers")
	_assert(ctx_a_restored.job_board.has_job(job_a.job_id) and ctx_a_restored.workplace_registry.has_workplace("mil_hq"), "Context round-trip preserves job_board and workplace_registry")
	_assert(not ctx_a_restored.add_villager(va), "Restored context still rejects previously removed villager ID (_1 < next_villager_seq)")
	_assert(SettlementVillagerContextScript.from_dict({"settlement_id": "stl_a", "origin_faction_id": "rival_military", "villagers": "not_an_array"}) == null, "Context from_dict rejects non-array villagers")

func _test_7_3_id_allocator() -> void:
	print("\n[7.3] Deterministic & Collision-Safe NPC ID Allocator")
	var ctx_1 := SettlementVillagerContextScript.new("stl_rival_military", "rival_military")
	var ctx_2 := SettlementVillagerContextScript.new("stl_neutral_tribe", "neutral_tribe")

	var id1 := ctx_1.allocate_villager_id()
	var id2 := ctx_1.allocate_villager_id()
	var id_other := ctx_2.allocate_villager_id()

	_assert(id1 == "npc_stl_rival_military_1", "First allocated ID is deterministic ('npc_stl_rival_military_1')")
	_assert(id2 == "npc_stl_rival_military_2", "Consecutive allocation increments sequence ('npc_stl_rival_military_2')")
	_assert(id_other == "npc_stl_neutral_tribe_1" and id_other != id1, "Independent per-settlement sequence; zero cross-settlement collision")

	# Settlement IDs containing underscores (including numeric suffixes) cannot collide
	var ctx_u1 := SettlementVillagerContextScript.new("stl_region_1", "rival_military")
	var ctx_u2 := SettlementVillagerContextScript.new("stl_region", "rival_military", "rival_military", 12)
	var id_u1 := ctx_u1.allocate_villager_id() # "npc_stl_region_1_1"
	var id_u2 := ctx_u2.allocate_villager_id() # "npc_stl_region_12"
	_assert(id_u1 == "npc_stl_region_1_1" and id_u2 == "npc_stl_region_12" and id_u1 != id_u2, "Underscore settlement IDs never collide")
	_assert(SettlementVillagerDataScript.parse_villager_sequence_for_settlement(id_u1, "stl_region") == -1, "parse_villager_sequence rejects prefix with extra underscore in suffix")

	# Removing a villager must never reuse its ID or allow re-insertion of the removed ID
	var v3 := ctx_1.create_and_add_villager("Hunter 3", "hunter")
	_assert(v3.villager_id == "npc_stl_rival_military_3", "Third ID is _3")
	var seq_before_remove := ctx_1.get_next_sequence()
	_assert(ctx_1.remove_villager(v3.villager_id), "Removed v3")
	var v4 := ctx_1.create_and_add_villager("Hunter 4", "hunter")
	_assert(v4.villager_id == "npc_stl_rival_military_4" and ctx_1.get_next_sequence() > seq_before_remove, "Removing villager does not reuse ID _3; allocates _4")
	_assert(not ctx_1.add_villager(v3), "Removed villager ID _3 cannot be re-inserted")

	# Duplicate insertion attempt does not corrupt sequence state
	var seq_now := ctx_1.get_next_sequence()
	var dup_v4 := SettlementVillagerDataScript.new(v4.villager_id, "stl_rival_military", "rival_military")
	_assert(not ctx_1.add_villager(dup_v4) and ctx_1.get_next_sequence() == seq_now, "Rejected duplicate insert preserves allocator sequence")

	# Restoring allocator from existing sequence produces expected next ID & blocks historical IDs
	var ctx_restored := SettlementVillagerContextScript.new("stl_rival_military", "rival_military", "rival_military", 1)
	_assert(ctx_restored.restore_allocator_state(10, ["npc_stl_rival_military_3"]), "restore_allocator_state(10) succeeds")
	_assert(ctx_restored.allocate_villager_id() == "npc_stl_rival_military_10", "Restored allocator produces _10 next")
	var retired_v3 := SettlementVillagerDataScript.new("npc_stl_rival_military_3", "stl_rival_military", "rival_military")
	var retired_v5 := SettlementVillagerDataScript.new("npc_stl_rival_military_5", "stl_rival_military", "rival_military")
	_assert(not ctx_restored.add_villager(retired_v3) and not ctx_restored.add_villager(retired_v5), "Retired/historical IDs below restored watermark (<10) are rejected on add_villager")

	# Restoring with existing villagers cannot reset sequence below an already allocated ID
	var v10 := SettlementVillagerDataScript.new("npc_stl_rival_military_10", "stl_rival_military", "rival_military")
	_assert(ctx_restored.add_villager(v10), "Claimed allocated _10")
	_assert(ctx_restored.restore_allocator_state(2) and ctx_restored.get_next_sequence() == 11, "restore_allocator_state(2) cannot reset sequence below existing _10")
	_assert(not ctx_restored.restore_allocator_state(0), "restore_allocator_state(0) rejected")
	_assert(not ctx_restored.restore_allocator_state(12, ["npc_other_settlement_1"]), "restore_allocator_state with foreign historical ID rejected")

	# Malformed settlement IDs handled safely
	var bad_ctx := SettlementVillagerContextScript.new("invalid id with spaces", "rival_military")
	_assert(not bad_ctx.is_valid() and bad_ctx.allocate_villager_id() == "", "Malformed settlement_id rejected safely")
	_assert(SettlementVillagerContextScript.format_villager_id("", 1) == "", "Empty settlement_id rejected by format_villager_id")
	_assert(SettlementVillagerContextScript.format_villager_id("stl_ok", 0) == "", "Non-positive sequence rejected by format_villager_id")

func _test_7_4_architectural_isolation() -> void:
	print("\n[7.4] Architectural Isolation & FactionData.population Invariance")
	var phase1_files: Array[String] = [
		"res://scripts/world/settlement_villager_data.gd",
		"res://scripts/world/settlement_job_board.gd",
		"res://scripts/world/settlement_workplace_registry.gd",
		"res://scripts/world/settlement_villager_context.gd"
	]
	var forbidden_tokens: Array[String] = [
		"CitizenController",
		"/root/ResourceManager",
		"ResourceManager.",
		"JobManager.",
		"WorkplaceManager.",
		"citizen_controller.gd",
		"job_manager.gd",
		"workplace_manager.gd",
		"resource_manager.gd"
	]
	for path in phase1_files:
		var f := FileAccess.open(path, FileAccess.READ)
		_assert(f != null, "Opened %s for static isolation audit" % path.get_file())
		if f != null:
			var code_lines := f.get_as_text().split("\n")
			var clean := true
			for line in code_lines:
				var trimmed := line.strip_edges()
				if trimmed.begins_with("#"):
					continue
				for tok in forbidden_tokens:
					if trimmed.find(tok) >= 0:
						clean = false
						printerr("Forbidden token '%s' in %s: %s" % [tok, path, trimmed])
			_assert(clean, "%s has zero code references to player CitizenController/ResourceManager/JobManager/WorkplaceManager" % path.get_file())

	# Verify FactionData.population is completely untouched by creating/mutating settlement contexts
	var fm := FactionManagerScript.new()
	var mil_pop_before: int = fm.get_faction("rival_military").population
	var mer_pop_before: int = fm.get_faction("rival_merchant").population
	var tri_pop_before: int = fm.get_faction("neutral_tribe").population

	var ctx := SettlementVillagerContextScript.new("stl_rival_military", "rival_military")
	for i in range(10):
		ctx.create_and_add_villager("NPC %d" % i, "guard")
	_assert(
		fm.get_faction("rival_military").population == mil_pop_before
		and fm.get_faction("rival_merchant").population == mer_pop_before
		and fm.get_faction("neutral_tribe").population == tri_pop_before,
		"FactionData.population remains completely unchanged (60 / 50 / 35)"
	)

func _test_7_5_external_id_insertion_and_getter_ownership() -> void:
	print("\n[7.5] Final Edge-Case Verification: External ID Insertion & Getter Ownership Contract")

	# --- Verification A: External Villager ID Insertion (Steps 1–10) ---
	# Step 1: Create a context whose next sequence is N = 5
	var ctx_ext := SettlementVillagerContextScript.new("stl_rival_military", "rival_military", "rival_military", 5)
	_assert(ctx_ext.get_next_sequence() == 5, "Step 1: Context initialized with next sequence N = 5")

	# Step 2–4: Construct villager externally with sequence N = 5, insert, verify allocator advances to 6
	var v_ext_n := SettlementVillagerDataScript.new(
		"npc_stl_rival_military_5",
		"stl_rival_military",
		"rival_military",
		"External Seq 5",
		"guard"
	)
	_assert(ctx_ext.add_villager(v_ext_n), "Step 3: External villager with sequence N = 5 inserted")
	_assert(ctx_ext.get_next_sequence() == 6 and ctx_ext.has_villager("npc_stl_rival_military_5"), "Step 4: Allocator advances from N = 5 to 6 after external insert")

	# Step 5–6: Construct another villager externally with sequence M = 12 (> N), insert, verify allocator advances to 13
	var v_ext_gt := SettlementVillagerDataScript.new(
		"npc_stl_rival_military_12",
		"stl_rival_military",
		"rival_military",
		"External Seq 12",
		"woodcutter"
	)
	_assert(ctx_ext.add_villager(v_ext_gt), "Step 6: External villager with sequence M = 12 (> N) inserted")
	_assert(ctx_ext.get_next_sequence() == 13 and ctx_ext.has_villager("npc_stl_rival_military_12"), "Step 6: Allocator advances to M + 1 = 13")

	# Step 7: Future allocator calls cannot generate an ID already present in the context
	var alloc_after_ext := ctx_ext.allocate_villager_id()
	var created_after_ext := ctx_ext.create_and_add_villager("Allocated 14", "farmer")
	_assert(
		alloc_after_ext == "npc_stl_rival_military_13"
		and not ctx_ext.has_villager(alloc_after_ext)
		and created_after_ext != null
		and created_after_ext.villager_id == "npc_stl_rival_military_14",
		"Step 7: Future allocator calls generate _13 and _14 and never collide with _5 or _12"
	)

	# Claim _13 so it is active before serialization
	var v_claimed_13 := SettlementVillagerDataScript.new("npc_stl_rival_military_13", "stl_rival_military", "rival_military", "Claimed 13", "hauler")
	_assert(ctx_ext.add_villager(v_claimed_13), "Step 7b: Claimed allocated _13 succeeds")

	# Step 8–9: Serialize and restore the context; verify next generated ID remains unique and follows restored sequence
	var ext_snapshot: Dictionary = ctx_ext.to_dict()
	var ctx_ext_restored = SettlementVillagerContextScript.from_dict(ext_snapshot)
	_assert(ctx_ext_restored != null and ctx_ext_restored.get_next_sequence() == 15, "Step 8: Context serialized and restored with next_villager_seq == 15")
	var next_id_after_restore: String = ctx_ext_restored.allocate_villager_id()
	_assert(
		next_id_after_restore == "npc_stl_rival_military_15"
		and not ctx_ext_restored.has_villager(next_id_after_restore),
		"Step 9: Restored context generates unique ID 'npc_stl_rival_military_15' following restored sequence"
	)

	# Step 10: Verify duplicate IDs, retired/skipped IDs (< 15), and cross-settlement IDs remain rejected
	var dup_5 := SettlementVillagerDataScript.new("npc_stl_rival_military_5", "stl_rival_military", "rival_military")
	var dup_12 := SettlementVillagerDataScript.new("npc_stl_rival_military_12", "stl_rival_military", "rival_military")
	var retired_4 := SettlementVillagerDataScript.new("npc_stl_rival_military_4", "stl_rival_military", "rival_military")
	var skipped_8 := SettlementVillagerDataScript.new("npc_stl_rival_military_8", "stl_rival_military", "rival_military")
	var foreign_v := SettlementVillagerDataScript.new("npc_stl_rival_merchant_16", "stl_rival_merchant", "rival_merchant")
	_assert(
		not ctx_ext_restored.add_villager(dup_5)
		and not ctx_ext_restored.add_villager(dup_12)
		and not ctx_ext_restored.add_villager(retired_4)
		and not ctx_ext_restored.add_villager(skipped_8)
		and not ctx_ext_restored.add_villager(foreign_v),
		"Step 10: Duplicate (_5, _12), retired/skipped (_4, _8), and cross-settlement IDs rejected after restore"
	)

	# --- Verification B: Getter and Object Ownership Semantics ---
	# 1. Villager getters: get_villager() returns live canonical reference; get_all_villagers() returns defensive Array copy of live canonical references
	var live_v5_by_id = ctx_ext_restored.get_villager("npc_stl_rival_military_5")
	live_v5_by_id.hunger = 42.5
	var all_villagers: Array = ctx_ext_restored.get_all_villagers()
	_assert(all_villagers.size() == 4 and is_equal_approx(all_villagers[0].hunger, 42.5), "Villager get_villager() & get_all_villagers() return live canonical SettlementVillagerData references")
	all_villagers[0].morale = 88.0
	_assert(is_equal_approx(ctx_ext_restored.get_villager("npc_stl_rival_military_5").morale, 88.0), "Mutating element from get_all_villagers() updates canonical villager state")
	all_villagers.clear()
	_assert(ctx_ext_restored.get_villager_count() == 4 and ctx_ext_restored.has_villager("npc_stl_rival_military_5"), "Mutating Array returned by get_all_villagers() does not alter internal context membership")
	var ctx_snap_before_mut: Dictionary = ctx_ext_restored.to_dict()
	live_v5_by_id.hunger = 99.0
	_assert(is_equal_approx(float(ctx_snap_before_mut["villagers"][0]["hunger"]), 42.5), "Context to_dict() snapshot remains independent of subsequent live villager mutations")

	# 2. JobBoard getters: get_job() returns live canonical reference; get_all_jobs() returns defensive Array copy of live canonical references
	var created_job = ctx_ext_restored.job_board.create_job_record("woodcutter", "mil_lumber_1", Vector2i(14, 15), 3.0, 5)
	var live_job = ctx_ext_restored.job_board.get_job(created_job.job_id)
	live_job.work_hours_done = 1.25
	var all_jobs: Array = ctx_ext_restored.job_board.get_all_jobs()
	_assert(all_jobs.size() == 1 and is_equal_approx(all_jobs[0].work_hours_done, 1.25), "JobBoard get_job() & get_all_jobs() return live canonical NpcJobRecord references")
	all_jobs[0].state = SettlementJobBoardScript.STATE_IN_PROGRESS
	_assert(ctx_ext_restored.job_board.get_job(created_job.job_id).state == SettlementJobBoardScript.STATE_IN_PROGRESS, "Mutating element from get_all_jobs() updates canonical job state")
	all_jobs.clear()
	_assert(ctx_ext_restored.job_board.get_job_count() == 1 and ctx_ext_restored.job_board.has_job(created_job.job_id), "Mutating Array returned by get_all_jobs() does not alter JobBoard membership")
	var jb_snap: Dictionary = ctx_ext_restored.job_board.to_dict()
	live_job.work_hours_done = 2.75
	_assert(is_equal_approx(float(jb_snap["jobs"][0]["work_hours_done"]), 1.25), "JobBoard to_dict() snapshot remains independent of subsequent live job mutations")

	# 3. WorkplaceRegistry getters: get_workplace() returns live canonical reference; get_all_workplaces() returns defensive Array copy of live canonical references
	ctx_ext_restored.workplace_registry.register_workplace("mil_lumber_1", "lumber_camp", Vector2i(14, 15), Vector2i(2, 2), Vector2i(14, 17), "wood", 40, 2, false)
	var live_wp = ctx_ext_restored.workplace_registry.get_workplace("mil_lumber_1")
	live_wp.buffer_amount = 15
	var all_wps: Array = ctx_ext_restored.workplace_registry.get_all_workplaces()
	_assert(all_wps.size() == 1 and all_wps[0].buffer_amount == 15, "WorkplaceRegistry get_workplace() & get_all_workplaces() return live canonical NpcWorkplaceRecord references")
	all_wps[0].worker_quota = 4
	_assert(ctx_ext_restored.workplace_registry.get_workplace("mil_lumber_1").worker_quota == 4, "Mutating element from get_all_workplaces() updates canonical workplace state")
	all_wps.clear()
	_assert(ctx_ext_restored.workplace_registry.get_workplace_count() == 1 and ctx_ext_restored.workplace_registry.has_workplace("mil_lumber_1"), "Mutating Array returned by get_all_workplaces() does not alter WorkplaceRegistry membership")
	var wr_snap: Dictionary = ctx_ext_restored.workplace_registry.to_dict()
	live_wp.buffer_amount = 30
	_assert(int(wr_snap["workplaces"][0]["buffer_amount"]) == 15, "WorkplaceRegistry to_dict() snapshot remains independent of subsequent live workplace mutations")

func _test_7_6_identity_and_ownership_immutability() -> void:
	print("\n[7.6] Identity and Ownership Immutability Audit")
	var ctx := SettlementVillagerContextScript.new("stl_rival_military", "rival_military")
	var v_created = ctx.create_and_add_villager("Lê Văn Kiên", "guard", Vector2i(12, 18))
	var orig_vid: String = v_created.villager_id

	# 1–4. Retrieve villager via get_villager() and attempt to mutate villager_id, settlement_id, origin_faction_id, and context identity
	var live_v = ctx.get_villager(orig_vid)
	live_v.villager_id = "npc_stl_corrupted_999"
	live_v.settlement_id = "stl_other_settlement"
	live_v.origin_faction_id = "corrupted_faction"
	ctx.settlement_id = "stl_other_settlement"
	ctx.origin_faction_id = "corrupted_faction"

	_assert(live_v.villager_id == orig_vid, "Villager villager_id is immutable after registration")
	_assert(live_v.settlement_id == "stl_rival_military", "Villager settlement_id is immutable after registration")
	_assert(live_v.origin_faction_id == "rival_military", "Villager origin_faction_id is immutable after registration")
	_assert(ctx.settlement_id == "stl_rival_military" and ctx.origin_faction_id == "rival_military", "Context settlement_id and origin_faction_id are immutable")
	_assert(ctx.has_villager(orig_vid) and ctx.get_villager(orig_vid) == live_v and not ctx.has_villager("npc_stl_corrupted_999"), "Context lookup dictionary and ownership remain uncorrupted")

	# 5. Verify legitimate simulation fields remain mutable on canonical reference
	live_v.hunger = 35.0
	live_v.fatigue = 40.0
	live_v.health = 92.0
	live_v.morale = 81.0
	live_v.cell = Vector2i(15, 22)
	live_v.task_state = SettlementVillagerDataScript.TASK_GUARDING
	_assert(
		is_equal_approx(ctx.get_villager(orig_vid).hunger, 35.0)
		and is_equal_approx(ctx.get_villager(orig_vid).fatigue, 40.0)
		and is_equal_approx(ctx.get_villager(orig_vid).health, 92.0)
		and is_equal_approx(ctx.get_villager(orig_vid).morale, 81.0)
		and ctx.get_villager(orig_vid).cell == Vector2i(15, 22)
		and ctx.get_villager(orig_vid).task_state == SettlementVillagerDataScript.TASK_GUARDING,
		"Legitimate simulation fields (hunger, fatigue, health, morale, cell, task_state) remain mutable"
	)

	# 6. Verify mutable affiliation fields retain intended flexibility (while rejecting invalid strings)
	live_v.current_faction_id = "emerging_power_1"
	live_v.home_settlement_id = "stl_resettled_home"
	ctx.owner_faction_id = "emerging_power_1"
	live_v.current_faction_id = ""
	live_v.home_settlement_id = "bad id with spaces"
	ctx.owner_faction_id = ""
	_assert(
		live_v.current_faction_id == "emerging_power_1"
		and live_v.home_settlement_id == "stl_resettled_home"
		and ctx.owner_faction_id == "emerging_power_1"
		and live_v.origin_faction_id == "rival_military"
		and live_v.settlement_id == "stl_rival_military",
		"Mutable affiliation fields (current_faction_id, home_settlement_id, owner_faction_id) update cleanly and reject invalid identifiers"
	)

	# 7. Job Record Identity & Operational Mutability
	var job_rec = ctx.job_board.create_job_record("guard", "mil_barracks_1", Vector2i(12, 18), 4.0, 8)
	var orig_jid: String = job_rec.job_id
	var live_job = ctx.job_board.get_job(orig_jid)
	live_job.job_id = "npc_job_corrupted_999"
	live_job.settlement_id = "stl_other_settlement"
	ctx.job_board.settlement_id = "stl_other_settlement"
	_assert(live_job.job_id == orig_jid and live_job.settlement_id == "stl_rival_military" and ctx.job_board.settlement_id == "stl_rival_military", "NpcJobRecord job_id and settlement_id are immutable after registration")
	_assert(ctx.job_board.has_job(orig_jid) and ctx.job_board.get_job(orig_jid) == live_job, "JobBoard lookup remains intact after attempted job_id mutation")

	live_job.state = SettlementJobBoardScript.STATE_IN_PROGRESS
	live_job.assigned_villager_id = orig_vid
	live_job.work_hours_done = 2.5
	live_job.priority = 10
	_assert(
		ctx.job_board.get_job(orig_jid).state == SettlementJobBoardScript.STATE_IN_PROGRESS
		and ctx.job_board.get_job(orig_jid).assigned_villager_id == orig_vid
		and is_equal_approx(ctx.job_board.get_job(orig_jid).work_hours_done, 2.5)
		and ctx.job_board.get_job(orig_jid).priority == 10,
		"Legitimate NpcJobRecord operational fields remain mutable"
	)

	# 8. Workplace Record Identity & Operational Mutability
	var wp_rec = ctx.workplace_registry.register_workplace("mil_barracks_1", "barracks", Vector2i(10, 16), Vector2i(3, 3), Vector2i(12, 19), "", 30, 3, true)
	var live_wp = ctx.workplace_registry.get_workplace("mil_barracks_1")
	live_wp.workplace_id = "wp_corrupted_999"
	live_wp.settlement_id = "stl_other_settlement"
	live_wp.building_id = "bld_corrupted_999"
	ctx.workplace_registry.settlement_id = "stl_other_settlement"
	_assert(
		live_wp.workplace_id == "mil_barracks_1"
		and live_wp.settlement_id == "stl_rival_military"
		and live_wp.building_id == "mil_barracks_1"
		and ctx.workplace_registry.settlement_id == "stl_rival_military",
		"NpcWorkplaceRecord workplace_id, settlement_id, and building_id are immutable after registration"
	)
	_assert(ctx.workplace_registry.has_workplace("mil_barracks_1") and ctx.workplace_registry.get_workplace("mil_barracks_1") == live_wp, "WorkplaceRegistry lookup remains intact after attempted workplace_id mutation")

	live_wp.worker_quota = 5
	live_wp.buffer_amount = 18
	live_wp.is_active = false
	_assert(
		ctx.workplace_registry.get_workplace("mil_barracks_1").worker_quota == 5
		and ctx.workplace_registry.get_workplace("mil_barracks_1").buffer_amount == 18
		and ctx.workplace_registry.get_workplace("mil_barracks_1").is_active == false,
		"Legitimate NpcWorkplaceRecord operational fields (worker_quota, buffer_amount, is_active) remain mutable"
	)

	# 9. Verify serialization/restoration preserves identity invariants, operational state, and locks restored records
	var restored_ctx = SettlementVillagerContextScript.from_dict(ctx.to_dict())
	_assert(restored_ctx != null, "Context round-trip after affiliation & operational updates succeeds")
	var rv = restored_ctx.get_villager(orig_vid)
	var rj = restored_ctx.job_board.get_job(orig_jid)
	var rw = restored_ctx.workplace_registry.get_workplace("mil_barracks_1")
	rv.villager_id = "mutated_after_restore"
	rv.settlement_id = "mutated_after_restore"
	rv.origin_faction_id = "mutated_after_restore"
	rj.job_id = "mutated_after_restore"
	rj.settlement_id = "mutated_after_restore"
	rw.workplace_id = "mutated_after_restore"
	rw.settlement_id = "mutated_after_restore"
	_assert(
		rv.villager_id == orig_vid
		and rv.settlement_id == "stl_rival_military"
		and rv.origin_faction_id == "rival_military"
		and rv.current_faction_id == "emerging_power_1"
		and rv.home_settlement_id == "stl_resettled_home"
		and rj.job_id == orig_jid
		and rj.settlement_id == "stl_rival_military"
		and rw.workplace_id == "mil_barracks_1"
		and rw.settlement_id == "stl_rival_military"
		and rw.is_active == false,
		"Restored villager, job, and workplace records preserve and lock identity invariants"
	)

	# 10. Verify removal of job, workplace, and villager works cleanly after attempted identity mutations
	_assert(restored_ctx.job_board.remove_job(orig_jid) and not restored_ctx.job_board.has_job(orig_jid), "Job removal succeeds after attempted identity mutation")
	_assert(restored_ctx.workplace_registry.unregister_workplace("mil_barracks_1") and not restored_ctx.workplace_registry.has_workplace("mil_barracks_1"), "Workplace removal succeeds after attempted identity mutation")
	_assert(restored_ctx.remove_villager(orig_vid) and not restored_ctx.has_villager(orig_vid), "Villager removal succeeds after attempted identity mutation")
