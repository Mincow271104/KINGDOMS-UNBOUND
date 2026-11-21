extends SceneTree
## Focused Phase 3 Test Suite: Rival Settlement Villager System — Functional Buildings, Housing & Jobs
## Covers Sections 16.1 through 16.8 plus Independent Hardening Reviews A–G (Architecture v1.0 — LOCKED).

const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementJobBoardScript = preload("res://scripts/world/settlement_job_board.gd")
const SettlementWorkplaceRegistryScript = preload("res://scripts/world/settlement_workplace_registry.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const SettlementBuildingCapabilityAdapterScript = preload("res://scripts/world/settlement_building_capability_adapter.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
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

func _build_canonical_settlement(sid: String, fid: String, tier: String, anchor: Vector2i = Vector2i(40, 40)) -> RefCounted:
	var layout: Dictionary = SettlementGeneratorScript._build_layout_template(fid, anchor, tier)
	var role: String = SettlementDataScript.ROLE_VILLAGE if fid == "neutral_tribe" else SettlementDataScript.ROLE_CAPITAL
	var stl := SettlementDataScript.new(sid, fid, fid, role, anchor, "outpost_%s" % fid)
	stl.layout_tier = tier
	for b in layout.get("buildings", []):
		stl.buildings.append((b as Dictionary).duplicate(true))
	for r in layout.get("roads", []):
		stl.roads.append(r)
	for dec in layout.get("decorations", []):
		stl.decorations.append((dec as Dictionary).duplicate(true))
	return stl

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Rival Settlement Buildings, Housing & Jobs (Phase 3)")
	print("========================================================")

	_test_16_1_layout_mapping()
	_test_16_2_housing_capacity()
	_test_16_3_workplace_registration()
	_test_16_4_storage_and_receiving()
	_test_16_5_hauling_feasibility()
	_test_16_6_job_generation_and_smith_restriction()
	_test_16_7_deterministic_villager_assignment()
	_test_16_8_reconciliation_idempotency_and_isolation()
	_test_review_a_neutral_tribe_hauler_reconciliation()
	_test_review_b_workplace_buffer_conservation()
	_test_review_c_storage_capacity_provenance_and_lifecycle()
	_test_review_d_e_f_workplace_contract_replacement_and_quotas()
	_test_final_audit_a_neutral_tribe_compact_workforce()
	_test_final_audit_b_military_full_guard_patrol()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_16_1_layout_mapping() -> void:
	print("\n[16.1] Canonical M1–M4 Layout Mapping Across All Six Settlement Variants")
	var mil_full := _build_canonical_settlement("stl_mil_full", "rival_military", "full")
	var mil_comp := _build_canonical_settlement("stl_mil_comp", "rival_military", "compact")
	var mer_full := _build_canonical_settlement("stl_mer_full", "rival_merchant", "full")
	var mer_comp := _build_canonical_settlement("stl_mer_comp", "rival_merchant", "compact")
	var neu_full := _build_canonical_settlement("stl_neu_full", "neutral_tribe", "full")
	var neu_comp := _build_canonical_settlement("stl_neu_comp", "neutral_tribe", "compact")

	_assert(mil_full.buildings.size() == 24, "Military Full has 24 canonical buildings (1 barracks, 1 storehouse, 2 houses, 4 watchtowers, 16 palisades)")
	_assert(mil_comp.buildings.size() == 3, "Military Compact has 3 canonical buildings (rival_military_hq, rival_military_sec_1, rival_military_house_1)")
	_assert(mer_full.buildings.size() == 6, "Merchant Full has 6 canonical buildings (mer_hq, mer_store_1, mer_store_2, mer_workshop, mer_house_1, mer_house_2)")
	_assert(mer_comp.buildings.size() == 2, "Merchant Compact has 2 canonical buildings (rival_merchant_hq, rival_merchant_sec_1)")
	_assert(neu_full.buildings.size() == 5, "Neutral Tribe Full has 5 canonical buildings (neu_hq, neu_wood, neu_farm, neu_house_1, neu_house_2)")
	_assert(neu_comp.buildings.size() == 2, "Neutral Tribe Compact has 2 canonical buildings (neutral_tribe_hq, neutral_tribe_sec_1)")

	var d_mil_f := SettlementBuildingCapabilityAdapterScript.derive_capabilities_from_buildings("stl_mil_full", "rival_military", mil_full.buildings)
	var d_mer_f := SettlementBuildingCapabilityAdapterScript.derive_capabilities_from_buildings("stl_mer_full", "rival_merchant", mer_full.buildings)
	var d_neu_f := SettlementBuildingCapabilityAdapterScript.derive_capabilities_from_buildings("stl_neu_full", "neutral_tribe", neu_full.buildings)
	_assert(bool(d_mil_f["ok"]) and bool(d_mer_f["ok"]) and bool(d_neu_f["ok"]), "Capability derivation succeeds on canonical layouts")

	# Unsupported building type handling (does not create workplace, jobs, housing, or storage)
	var custom_list: Array[Dictionary] = [
		{"id": "totem_1", "type": "sacred_totem", "cell": Vector2i(10, 10), "size": Vector2i(1, 1)}
	]
	var d_custom := SettlementBuildingCapabilityAdapterScript.derive_capabilities_from_buildings("stl_custom", "neutral_tribe", custom_list)
	_assert(
		bool(d_custom["ok"])
		and int(d_custom["housing_capacity"]) == 0
		and (d_custom["job_descriptors"] as Array).is_empty()
		and (d_custom["building_descriptors"][0]["capabilities"] as Array).has(SettlementBuildingCapabilityAdapterScript.CAP_UNSUPPORTED),
		"Unsupported building type is classified safely without fabricating workplaces, jobs, or housing"
	)

func _test_16_2_housing_capacity() -> void:
	print("\n[16.2] Locked Housing Capacity Matrix & Edge Cases")
	var mil_full := _build_canonical_settlement("stl_mil_full", "rival_military", "full")
	var mil_comp := _build_canonical_settlement("stl_mil_comp", "rival_military", "compact")
	var mer_full := _build_canonical_settlement("stl_mer_full", "rival_merchant", "full")
	var mer_comp := _build_canonical_settlement("stl_mer_comp", "rival_merchant", "compact")
	var neu_full := _build_canonical_settlement("stl_neu_full", "neutral_tribe", "full")
	var neu_comp := _build_canonical_settlement("stl_neu_comp", "neutral_tribe", "compact")

	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity(mil_full.buildings, "rival_military") == 12, "Military Full housing capacity == 12 (2 Houses)")
	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity(mil_comp.buildings, "rival_military") == 6, "Military Compact housing capacity == 6 (1 House)")
	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity(mer_full.buildings, "rival_merchant") == 12, "Merchant Full housing capacity == 12 (2 Houses)")
	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity(mer_comp.buildings, "rival_merchant") == 4, "Merchant Compact housing capacity == 4 (Market HQ baseline)")
	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity(neu_full.buildings, "neutral_tribe") == 12, "Neutral Tribe Full housing capacity == 12 (2 Houses)")
	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity(neu_comp.buildings, "neutral_tribe") == 4, "Neutral Tribe Compact housing capacity == 4 (Townhall HQ baseline)")

	# Edge cases: empty settlement, Military Compact without house (must NOT receive HQ baseline 4), duplicate house, malformed building
	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity([], "rival_military") == 0, "Empty settlement housing capacity == 0")
	var mil_no_house: Array[Dictionary] = [
		{"id": "rival_military_hq", "type": "barracks", "cell": Vector2i(10, 10), "size": Vector2i(3, 3), "role": "hq"}
	]
	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity(mil_no_house, "rival_military") == 0, "Barracks HQ without house does NOT receive HQ baseline 4 (capacity == 0)")

	var dup_houses: Array[Dictionary] = [
		{"id": "h1", "type": "house", "cell": Vector2i(10, 10), "size": Vector2i(2, 2)},
		{"id": "h1", "type": "house", "cell": Vector2i(10, 10), "size": Vector2i(2, 2)},
		{"id": "h1_dup_cell", "type": "house", "cell": Vector2i(10, 10), "size": Vector2i(2, 2)},
		{"id": "", "type": "house", "cell": Vector2i(20, 20), "size": Vector2i(2, 2)},
		{"id": "bad_size", "type": "house", "cell": Vector2i(25, 25), "size": Vector2i(0, -2)}
	]
	_assert(SettlementBuildingCapabilityAdapterScript.calculate_housing_capacity(dup_houses, "rival_military") == 6, "Duplicate house IDs/cells and malformed records are not double-counted (capacity == 6)")

	# Context housing slot queries (below, at, and above capacity) without creating/removing villagers
	var ctx := SettlementVillagerContextScript.new("stl_mer_comp", "rival_merchant")
	ctx.reconcile_buildings(mer_comp)
	_assert(ctx.get_housing_capacity() == 4 and ctx.get_available_housing_slots() == 4 and not ctx.is_at_housing_capacity(), "Merchant Compact starts with 4 available housing slots and 0 villagers")
	for i in range(4):
		ctx.create_and_add_villager("Merchant %d" % (i + 1), "idle", Vector2i(40, 40))
	_assert(ctx.get_villager_count() == 4 and ctx.get_available_housing_slots() == 0 and ctx.is_at_housing_capacity(), "At 4 villagers, Merchant Compact has 0 available slots and is_at_housing_capacity() == true")
	ctx.create_and_add_villager("Merchant 5 (Over)", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(mer_comp)
	_assert(ctx.get_villager_count() == 5 and ctx.get_available_housing_slots() == 0 and ctx.is_at_housing_capacity(), "Above capacity (5 > 4), available slots == 0 and reconcile_buildings never deletes villagers")

func _test_16_3_workplace_registration() -> void:
	print("\n[16.3] Workplace Registry Integration & Stable Workplace IDs")
	var ctx_mil := SettlementVillagerContextScript.new("stl_mil_full", "rival_military")
	var mil_full := _build_canonical_settlement("stl_mil_full", "rival_military", "full")
	var res := ctx_mil.reconcile_buildings(mil_full)

	_assert(bool(res["ok"]) and ctx_mil.workplace_registry.get_workplace_count() == 2, "Military Full registers 2 workplaces (mil_hq barracks, mil_store storehouse)")
	var wp_hq = ctx_mil.workplace_registry.get_workplace("mil_hq")
	var wp_store = ctx_mil.workplace_registry.get_workplace("mil_store")
	_assert(wp_hq != null and wp_hq.building_id == "mil_hq" and wp_hq.worker_quota == 2 and wp_hq.is_active, "mil_hq registered with building_id='mil_hq' and worker_quota=2")
	_assert(wp_store != null and wp_store.building_id == "mil_store" and wp_store.worker_quota == 2 and wp_store.is_dropoff and wp_store.is_active, "mil_store registered with worker_quota=2 and is_dropoff=true")

	# Reject cross-settlement building source
	var foreign_stl := _build_canonical_settlement("stl_foreign", "rival_military", "compact")
	_assert(not bool(ctx_mil.reconcile_buildings(foreign_stl).get("ok", false)), "reconcile_buildings rejects SettlementData belonging to another settlement")

func _test_16_4_storage_and_receiving() -> void:
	print("\n[16.4] Storage Capacities, Receiving Buffers, HQ Fallback & Over-Capacity Safety")
	var ctx_mil_f := SettlementVillagerContextScript.new("stl_mil_full", "rival_military")
	var ctx_mil_c := SettlementVillagerContextScript.new("stl_mil_comp", "rival_military")
	var ctx_mer_f := SettlementVillagerContextScript.new("stl_mer_full", "rival_merchant")
	var ctx_neu_c := SettlementVillagerContextScript.new("stl_neu_comp", "neutral_tribe")

	ctx_mil_f.reconcile_buildings(_build_canonical_settlement("stl_mil_full", "rival_military", "full"))
	ctx_mil_c.reconcile_buildings(_build_canonical_settlement("stl_mil_comp", "rival_military", "compact"))
	ctx_mer_f.reconcile_buildings(_build_canonical_settlement("stl_mer_full", "rival_merchant", "full"))
	ctx_neu_c.reconcile_buildings(_build_canonical_settlement("stl_neu_comp", "neutral_tribe", "compact"))

	# Base food capacity is 500; each storehouse/townhall adds +500
	_assert(ctx_mil_f.economy.get_capacity("food") == 1000, "Military Full food capacity == 1000 (500 base + 500 mil_store)")
	_assert(ctx_mil_c.economy.get_capacity("food") == 500, "Military Compact food capacity == 500 (Barracks HQ fallback)")
	_assert(ctx_mer_f.economy.get_capacity("food") == 1500, "Merchant Full food capacity == 1500 (500 base + 2 * 500 storehouses)")
	_assert(ctx_neu_c.economy.get_capacity("food") == 1000, "Neutral Tribe Compact food capacity == 1000 (500 base + 500 Townhall HQ)")

	# Final storage & receiving buffer IDs
	_assert(ctx_mil_f.get_final_storage_ids() == ["mil_store"] and ctx_mil_f.get_receiving_buffer_ids() == ["mil_hq"], "Military Full has receiving buffer 'mil_hq' and final storage 'mil_store'")
	_assert(ctx_mil_c.get_final_storage_ids() == ["rival_military_hq"] and ctx_mil_c.get_receiving_buffer_ids().is_empty(), "Military Compact uses 'rival_military_hq' Barracks as final storage fallback with no separate receiving buffer")
	_assert(ctx_neu_c.get_final_storage_ids() == ["neutral_tribe_hq"], "Neutral Tribe Compact uses 'neutral_tribe_hq' Townhall as final storage fallback")

	# Decreasing capacity when a storage building is removed must NEVER destroy existing inventory
	ctx_mil_f.economy.credit_resource("food", 600, "convoy_supply", "stock_up", 10) # 80 + 600 = 680 (> 500 base)
	_assert(ctx_mil_f.economy.get_resource("food") == 680, "Military Full food stock is 680 / 1000")
	# Reconcile with mil_store removed (only mil_hq and houses remain -> food capacity drops to 500)
	var reduced_blds: Array[Dictionary] = [
		{"id": "mil_hq", "type": "barracks", "cell": Vector2i(39, 36), "size": Vector2i(3, 3), "role": "hq"}
	]
	var red_res := ctx_mil_f.reconcile_buildings(reduced_blds)
	_assert(
		bool(red_res["ok"])
		and ctx_mil_f.economy.get_capacity("food") == 500
		and ctx_mil_f.economy.get_resource("food") == 680
		and ctx_mil_f.economy.is_over_capacity("food")
		and int(ctx_mil_f.economy.get_over_capacity_resources().get("food", 0)) == 180
		and ctx_mil_f.economy.is_valid(),
		"Removing storehouse lowers food capacity to 500 without destroying any of the 680 food stock (180 over-capacity recorded safely)"
	)

func _test_16_5_hauling_feasibility() -> void:
	print("\n[16.5] Hauling Feasibility & Transport Route Validation")
	var ctx_mil_f := SettlementVillagerContextScript.new("stl_mil_full", "rival_military")
	var ctx_mil_c := SettlementVillagerContextScript.new("stl_mil_comp", "rival_military")
	var ctx_mer_f := SettlementVillagerContextScript.new("stl_mer_full", "rival_merchant")
	var ctx_mer_c := SettlementVillagerContextScript.new("stl_mer_comp", "rival_merchant")
	var ctx_neu_f := SettlementVillagerContextScript.new("stl_neu_full", "neutral_tribe")
	var ctx_neu_c := SettlementVillagerContextScript.new("stl_neu_comp", "neutral_tribe")

	ctx_mil_f.reconcile_buildings(_build_canonical_settlement("stl_mil_full", "rival_military", "full"))
	ctx_mil_c.reconcile_buildings(_build_canonical_settlement("stl_mil_comp", "rival_military", "compact"))
	ctx_mer_f.reconcile_buildings(_build_canonical_settlement("stl_mer_full", "rival_merchant", "full"))
	ctx_mer_c.reconcile_buildings(_build_canonical_settlement("stl_mer_comp", "rival_merchant", "compact"))
	ctx_neu_f.reconcile_buildings(_build_canonical_settlement("stl_neu_full", "neutral_tribe", "full"))
	ctx_neu_c.reconcile_buildings(_build_canonical_settlement("stl_neu_comp", "neutral_tribe", "compact"))

	_assert(ctx_mil_f.get_transport_routes().size() == 1 and ctx_mil_f.get_transport_routes()[0]["source_building_id"] == "mil_hq" and ctx_mil_f.get_transport_routes()[0]["dest_building_id"] == "mil_store", "Military Full has 1 valid transport route: mil_hq -> mil_store")
	_assert(ctx_mil_c.get_transport_routes().is_empty(), "Military Compact has 0 transport routes (no fake Barracks -> Barracks route)")
	_assert(ctx_mer_f.get_transport_routes().size() == 2, "Merchant Full has 2 valid transport routes: mer_hq -> mer_store_1 and mer_hq -> mer_store_2")
	_assert(ctx_mer_c.get_transport_routes().size() == 1 and ctx_mer_c.get_transport_routes()[0]["source_building_id"] == "rival_merchant_hq" and ctx_mer_c.get_transport_routes()[0]["dest_building_id"] == "rival_merchant_sec_1", "Merchant Compact has 1 valid transport route: rival_merchant_hq -> rival_merchant_sec_1")
	_assert(ctx_neu_f.get_transport_routes().size() == 2, "Neutral Tribe Full has 2 valid output-buffer routes to Townhall (neu_wood -> neu_hq and neu_farm -> neu_hq)")
	_assert(ctx_neu_c.get_transport_routes().size() == 1 and ctx_neu_c.get_transport_routes()[0]["source_building_id"] == "neutral_tribe_sec_1" and ctx_neu_c.get_transport_routes()[0]["dest_building_id"] == "neutral_tribe_hq", "Neutral Tribe Compact has 1 valid woodcutter output-buffer route: neutral_tribe_sec_1 -> neutral_tribe_hq")

	# Direct route validation rejection checks
	var sample_src: Dictionary = ctx_mer_c.get_building_descriptors()[0]
	var sample_dst: Dictionary = ctx_mer_c.get_building_descriptors()[1]
	_assert(not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_mer_comp", sample_src, sample_src, "food").get("ok", false)), "Same source and destination route rejected")
	_assert(not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_mer_comp", null, sample_dst, "food").get("ok", false)), "Missing source route rejected")
	_assert(not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_mer_comp", sample_src, null, "food").get("ok", false)), "Missing destination route rejected")
	_assert(not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_other", sample_src, sample_dst, "food").get("ok", false)), "Cross-settlement route rejected")
	_assert(not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_mer_comp", sample_src, sample_dst, "invalid_res").get("ok", false)), "Unsupported transport resource rejected")

func _test_16_6_job_generation_and_smith_restriction() -> void:
	print("\n[16.6] Deterministic Job Generation & Merchant Smith Restriction")
	var ctx_mil_f := SettlementVillagerContextScript.new("stl_mil_full", "rival_military")
	var ctx_mil_c := SettlementVillagerContextScript.new("stl_mil_comp", "rival_military")
	var ctx_mer_f := SettlementVillagerContextScript.new("stl_mer_full", "rival_merchant")
	var ctx_mer_c := SettlementVillagerContextScript.new("stl_mer_comp", "rival_merchant")
	var ctx_neu_f := SettlementVillagerContextScript.new("stl_neu_full", "neutral_tribe")
	var ctx_neu_c := SettlementVillagerContextScript.new("stl_neu_comp", "neutral_tribe")

	ctx_mil_f.reconcile_buildings(_build_canonical_settlement("stl_mil_full", "rival_military", "full"))
	ctx_mil_c.reconcile_buildings(_build_canonical_settlement("stl_mil_comp", "rival_military", "compact"))
	ctx_mer_f.reconcile_buildings(_build_canonical_settlement("stl_mer_full", "rival_merchant", "full"))
	ctx_mer_c.reconcile_buildings(_build_canonical_settlement("stl_mer_comp", "rival_merchant", "compact"))
	ctx_neu_f.reconcile_buildings(_build_canonical_settlement("stl_neu_full", "neutral_tribe", "full"))
	ctx_neu_c.reconcile_buildings(_build_canonical_settlement("stl_neu_comp", "neutral_tribe", "compact"))

	_assert(ctx_mil_f.job_board.get_job_count() == 4, "Military Full generates 4 job slots (2 Guard on mil_hq + 2 Hauler on mil_store)")
	_assert(ctx_mil_c.job_board.get_job_count() == 2, "Military Compact generates 2 job slots (2 Guard on rival_military_hq, 0 Hauler)")
	_assert(ctx_mer_f.job_board.get_job_count() == 4, "Merchant Full generates 4 job slots (2 Hauler on mer_store_1 + 2 Hauler on mer_store_2, 0 Smith)")
	_assert(ctx_mer_c.job_board.get_job_count() == 2, "Merchant Compact generates 2 job slots (2 Hauler on rival_merchant_sec_1)")
	_assert(ctx_neu_f.job_board.get_job_count() == 11, "Neutral Tribe Full generates 11 job slots (5 Farmer on neu_farm + 4 Woodcutter on neu_wood + 2 Hauler on neu_hq)")
	_assert(ctx_neu_c.job_board.get_job_count() == 3, "Neutral Tribe Compact generates 3 job slots (2 Woodcutter on neutral_tribe_sec_1 + 1 conditional Hauler on neutral_tribe_hq)")

	# Verify Merchant Workshop is registered as inactive with 0 Smith jobs
	var wp_workshop = ctx_mer_f.workplace_registry.get_workplace("mer_workshop")
	_assert(wp_workshop != null and not wp_workshop.is_active and wp_workshop.worker_quota == 0, "Merchant Full mer_workshop is registered with is_active=false and worker_quota=0")
	var any_smith_job: bool = false
	for j in ctx_mer_f.job_board.get_all_jobs():
		if j.job_type == "smith":
			any_smith_job = true
	_assert(not any_smith_job, "Zero Smith jobs are generated on Merchant Full without sustainable Ore")

func _test_16_7_deterministic_villager_assignment() -> void:
	print("\n[16.7] Deterministic Initial Villager Assignment & Priority Ordering")
	var ctx := SettlementVillagerContextScript.new("stl_mil_full", "rival_military")
	var mil_full := _build_canonical_settlement("stl_mil_full", "rival_military", "full")

	# Create 6 villagers for a settlement with 4 job slots (2 Guard @ priority 10, 2 Hauler @ priority 6)
	var v1 = ctx.create_and_add_villager("NPC 1", "idle", Vector2i(40, 40))
	var v2 = ctx.create_and_add_villager("NPC 2", "idle", Vector2i(40, 40))
	var v3 = ctx.create_and_add_villager("NPC 3", "idle", Vector2i(40, 40))
	var v4 = ctx.create_and_add_villager("NPC 4", "idle", Vector2i(40, 40))
	var v5 = ctx.create_and_add_villager("NPC 5", "idle", Vector2i(40, 40))
	var v6 = ctx.create_and_add_villager("NPC 6", "idle", Vector2i(40, 40))

	var rec_res := ctx.reconcile_buildings(mil_full)
	_assert(bool(rec_res["ok"]) and int(rec_res["assigned_villager_count"]) == 4 and int(rec_res["idle_villager_count"]) == 2, "4 villagers assigned to 4 open slots; 2 excess villagers remain idle")
	_assert(v1.role == "guard" and v2.role == "guard", "First 2 villagers (by sequence) receive higher-priority Guard jobs (priority 10)")
	_assert(v3.role == "hauler" and v4.role == "hauler", "Next 2 villagers receive Hauler jobs (priority 6)")
	_assert(v5.role == "idle" and v5.active_job_id == "" and v6.role == "idle" and v6.active_job_id == "", "Excess villagers 5 and 6 remain safely Idle with empty active_job_id")
	_assert(not v1.home_building_id.is_empty() and not v6.home_building_id.is_empty(), "Villagers receive deterministic residential home_building_id assignments")

	# Verify 1:1 uniqueness across all assigned jobs
	var seen_jobs: Dictionary = {}
	var dup_found: bool = false
	for v in [v1, v2, v3, v4]:
		if seen_jobs.has(v.active_job_id):
			dup_found = true
		seen_jobs[v.active_job_id] = v.villager_id
		var j = ctx.job_board.get_job(v.active_job_id)
		if j == null or j.assigned_villager_id != v.villager_id:
			dup_found = true
	_assert(not dup_found and seen_jobs.size() == 4 and bool(ctx.verify_assignment_integrity().get("ok", false)), "Strict 1:1 bijection between assigned villagers and job records")

func _test_16_8_reconciliation_idempotency_and_isolation() -> void:
	print("\n[16.8] Reconciliation Idempotency, Stale Cleanup, Atomic Validation & Isolation")
	var ctx := SettlementVillagerContextScript.new("stl_neu_full", "neutral_tribe")
	var neu_full := _build_canonical_settlement("stl_neu_full", "neutral_tribe", "full")
	var orig_buildings_snapshot: Array = neu_full.buildings.duplicate(true)

	for i in range(8):
		ctx.create_and_add_villager("Tribe %d" % (i + 1), "idle", Vector2i(40, 40))

	ctx.reconcile_buildings(neu_full)
	var snap_1: Dictionary = ctx.to_dict()
	var next_seq_1: int = ctx.get_next_sequence()

	# Re-run reconciliation 4 more times on the same canonical layout
	for _run in range(4):
		ctx.reconcile_buildings(neu_full)

	_assert(ctx.to_dict() == snap_1 and ctx.get_next_sequence() == next_seq_1, "Running reconcile_buildings 5 times is 100% idempotent (workplaces, jobs, housing, storage, assignments, and allocator sequence unchanged)")
	_assert(neu_full.buildings == orig_buildings_snapshot, "Canonical SettlementData.buildings geometry/schema is never mutated")

	# Malformed replacement input must abort before mutating existing valid state
	var malformed_blds: Array = [
		{"id": "", "type": "house", "cell": Vector2i(10, 10), "size": Vector2i(2, 2)}
	]
	var bad_res := ctx.reconcile_buildings(malformed_blds, true)
	_assert(not bool(bad_res["ok"]) and ctx.to_dict() == snap_1, "Malformed building input aborts atomically and preserves previous valid derived state")

	# Legitimate building removal: remove neu_farm (5 Farmer slots) -> neu_wood (4 Woodcutter) + neu_hq (2 Hauler) = 6 slots remain
	var without_farm: Array[Dictionary] = []
	for b in neu_full.buildings:
		if String(b["id"]) != "neu_farm":
			without_farm.append((b as Dictionary).duplicate(true))
	var rem_res := ctx.reconcile_buildings(without_farm)
	_assert(
		bool(rem_res["ok"])
		and not ctx.workplace_registry.has_workplace("neu_farm")
		and ctx.job_board.get_job_count() == 6
		and int(rem_res["assigned_villager_count"]) == 6
		and int(rem_res["idle_villager_count"]) == 2
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Removing neu_farm unregisters workplace, removes its 5 Farmer jobs, assigns 6 villagers (4 Woodcutter + 2 Hauler), and sets 2 excess villagers to Idle"
	)

	# Static & runtime isolation check
	var phase3_files: Array[String] = [
		"res://scripts/world/settlement_building_capability_adapter.gd",
		"res://scripts/world/settlement_villager_context.gd"
	]
	var forbidden_tokens: Array[String] = [
		"CitizenController",
		"/root/ResourceManager",
		"ResourceManager.",
		"JobManager.",
		"WorkplaceManager.",
		"buildings_by_cell",
		"FactionData"
	]
	for path in phase3_files:
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
			_assert(clean, "%s has zero code references to player JobManager/WorkplaceManager/CitizenController/ResourceManager/buildings_by_cell/FactionData" % path.get_file())

	var fm := FactionManagerScript.new()
	_assert(
		fm.get_faction("rival_military").population == 60
		and fm.get_faction("rival_merchant").population == 50
		and fm.get_faction("neutral_tribe").population == 35,
		"FactionData.population remains completely untouched (60 / 50 / 35)"
	)

func _test_review_a_neutral_tribe_hauler_reconciliation() -> void:
	print("\n[Review A] Neutral Tribe Full Hauler-to-Townhall Architecture Reconciliation")
	var ctx := SettlementVillagerContextScript.new("stl_neu_full_a", "neutral_tribe")
	var neu_full := _build_canonical_settlement("stl_neu_full_a", "neutral_tribe", "full")

	# Populate all 12 housing slots in Neutral Tribe Full
	for i in range(12):
		ctx.create_and_add_villager("Tribe Member %d" % (i + 1), "idle", Vector2i(40, 40))

	var rec := ctx.reconcile_buildings(neu_full)
	_assert(bool(rec["ok"]), "Review A.0: Neutral Tribe Full reconciliation succeeds")

	var routes: Array[Dictionary] = ctx.get_transport_routes()
	var has_farm_route: bool = false
	var has_wood_route: bool = false
	for r in routes:
		if r["source_building_id"] == "neu_farm" and r["dest_building_id"] == "neu_hq" and r["cargo_resource"] == "food":
			has_farm_route = true
		elif r["source_building_id"] == "neu_wood" and r["dest_building_id"] == "neu_hq" and r["cargo_resource"] == "wood":
			has_wood_route = true

	_assert(has_farm_route, "Review A.1: Farm -> Townhall ('neu_farm' -> 'neu_hq', food) valid output-buffer route exists")
	_assert(has_wood_route, "Review A.2: Woodcutter -> Townhall ('neu_wood' -> 'neu_hq', wood) valid output-buffer route exists")

	# Count assigned villager roles across the 12 villagers (5 Farmer + 4 Woodcutter + 2 Hauler + 1 Idle = 12)
	var role_counts: Dictionary = {"farmer": 0, "woodcutter": 0, "hauler": 0, "idle": 0}
	for v in ctx.get_all_villagers():
		role_counts[v.role] = int(role_counts.get(v.role, 0)) + 1
	_assert(
		int(role_counts["farmer"]) == 5
		and int(role_counts["woodcutter"]) == 4
		and int(role_counts["hauler"]) == 2
		and int(role_counts["idle"]) == 1,
		"Review A.2b: Neutral Tribe Full at 12 villagers assigns 5 Farmer, 4 Woodcutter, 2 Hauler to Townhall, and 1 Idle"
	)

	# Case 3: Same building as source and destination rejected
	var hq_desc: Dictionary = {}
	var farm_desc: Dictionary = {}
	for d in ctx.get_building_descriptors():
		if d["building_id"] == "neu_hq":
			hq_desc = d
		elif d["building_id"] == "neu_farm":
			farm_desc = d
	_assert(
		not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_neu_full_a", hq_desc, hq_desc, "food").get("ok", false))
		and not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_neu_full_a", farm_desc, farm_desc, "food").get("ok", false)),
		"Review A.3: Same building as source and destination is rejected"
	)

	# Case 4: Production building without a valid output buffer (buffer_capacity == 0 or inactive workshop) must NOT become a fake source
	var no_buf_blds: Array[Dictionary] = [
		{"id": "neu_hq", "type": "townhall", "cell": Vector2i(39, 39), "size": Vector2i(3, 3), "role": "hq"},
		{"id": "farm_no_buf", "type": "farm", "cell": Vector2i(43, 39), "size": Vector2i(2, 2), "role": "production", "buffer_capacity": 0},
		{"id": "inactive_ws", "type": "workshop", "cell": Vector2i(35, 39), "size": Vector2i(2, 2), "role": "production"}
	]
	var d_no_buf := SettlementBuildingCapabilityAdapterScript.derive_capabilities_from_buildings("stl_no_buf", "neutral_tribe", no_buf_blds)
	var any_hauler_in_no_buf: bool = false
	for jd in d_no_buf["job_descriptors"]:
		if jd["job_type"] == "hauler":
			any_hauler_in_no_buf = true
	_assert(
		bool(d_no_buf["ok"])
		and (d_no_buf["transport_routes"] as Array).is_empty()
		and (d_no_buf["output_buffer_ids"] as Array).is_empty()
		and not any_hauler_in_no_buf,
		"Review A.4: Production buildings without a valid output buffer (buffer_capacity=0 or inactive workshop) never become fake transport sources or generate Hauler jobs"
	)

	# Case 5: Unsupported resources rejected on Farm -> Townhall
	_assert(
		not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_neu_full_a", farm_desc, hq_desc, "wood").get("ok", false))
		and not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_neu_full_a", farm_desc, hq_desc, "gold").get("ok", false))
		and not bool(SettlementBuildingCapabilityAdapterScript.validate_transport_route("stl_neu_full_a", farm_desc, hq_desc, "unknown").get("ok", false)),
		"Review A.5: Incompatible or unsupported resources ('wood', 'gold', 'unknown') on Farm -> Townhall are rejected"
	)

	# Case 6: Repeated reconciliation does not duplicate routes or Hauler jobs
	for _i in range(3):
		ctx.reconcile_buildings(neu_full)
	_assert(
		ctx.get_transport_routes().size() == 2 and ctx.job_board.get_job_count() == 11,
		"Review A.6: Repeated reconciliation preserves exact 2 routes and 11 jobs without duplication"
	)

func _test_review_b_workplace_buffer_conservation() -> void:
	print("\n[Review B] Workplace Buffer Resource Preservation & Over-Capacity Lifecycle")
	var ctx := SettlementVillagerContextScript.new("stl_buf_test", "neutral_tribe")
	var base_blds: Array[Dictionary] = [
		{"id": "neu_hq", "type": "townhall", "cell": Vector2i(39, 39), "size": Vector2i(3, 3), "role": "hq"},
		{"id": "neu_farm", "type": "farm", "cell": Vector2i(43, 39), "size": Vector2i(2, 2), "role": "production", "buffer_capacity": 50},
		{"id": "neu_wood", "type": "woodcutter", "cell": Vector2i(35, 39), "size": Vector2i(2, 2), "role": "production", "buffer_capacity": 50}
	]
	ctx.reconcile_buildings(base_blds)

	# Case 1: Buffer 40, new capacity 20
	_assert(bool(ctx.deposit_to_workplace_buffer("neu_farm", 40).get("ok", false)), "Review B.0: Deposited 40 food into neu_farm buffer (capacity 50)")
	var reduced_blds: Array[Dictionary] = [
		{"id": "neu_hq", "type": "townhall", "cell": Vector2i(39, 39), "size": Vector2i(3, 3), "role": "hq"},
		{"id": "neu_farm", "type": "farm", "cell": Vector2i(43, 39), "size": Vector2i(2, 2), "role": "production", "buffer_capacity": 20},
		{"id": "neu_wood", "type": "woodcutter", "cell": Vector2i(35, 39), "size": Vector2i(2, 2), "role": "production", "buffer_capacity": 20}
	]
	ctx.reconcile_buildings(reduced_blds)
	var wp_farm = ctx.workplace_registry.get_workplace("neu_farm")
	_assert(
		wp_farm.buffer_amount == 40
		and ctx.get_workplace_effective_buffer_capacity("neu_farm") == 20
		and ctx.is_workplace_buffer_over_capacity("neu_farm")
		and ctx.get_workplace_buffer_over_capacity_amount("neu_farm") == 20,
		"Review B.1: Buffer 40 with new capacity 20 preserves all 40 units and reports 20 over-capacity without clamping"
	)

	# Case 2 & 3: Buffer 20 with new capacity 20, and Buffer 10 with new capacity 20
	_assert(bool(ctx.deposit_to_workplace_buffer("neu_wood", 10).get("ok", false)), "Review B.2a: Deposited 10 wood into neu_wood (10 / 20)")
	ctx.reconcile_buildings(reduced_blds)
	_assert(
		ctx.workplace_registry.get_workplace("neu_wood").buffer_amount == 10
		and ctx.get_workplace_effective_buffer_capacity("neu_wood") == 20
		and not ctx.is_workplace_buffer_over_capacity("neu_wood"),
		"Review B.3: Buffer 10 with new capacity 20 preserves 10 units and is not over-capacity"
	)
	_assert(bool(ctx.deposit_to_workplace_buffer("neu_wood", 10).get("ok", false)), "Review B.2b: Deposited 10 more wood into neu_wood (20 / 20)")
	ctx.reconcile_buildings(reduced_blds)
	_assert(
		ctx.workplace_registry.get_workplace("neu_wood").buffer_amount == 20
		and ctx.get_workplace_effective_buffer_capacity("neu_wood") == 20
		and not ctx.is_workplace_buffer_over_capacity("neu_wood")
		and not bool(ctx.deposit_to_workplace_buffer("neu_wood", 1).get("ok", false)),
		"Review B.2: Buffer 20 with new capacity 20 preserves 20 units, is at exact capacity, and blocks additional deposit"
	)

	# Case 4: Full buffer (50 / 50) followed by capacity reduction to 20
	ctx.set_workplace_buffer_capacity("neu_wood", 50)
	_assert(bool(ctx.deposit_to_workplace_buffer("neu_wood", 30).get("ok", false)), "Review B.4a: Filled neu_wood buffer to 50 / 50")
	ctx.reconcile_buildings(reduced_blds)
	_assert(
		ctx.workplace_registry.get_workplace("neu_wood").buffer_amount == 50
		and ctx.get_workplace_effective_buffer_capacity("neu_wood") == 20
		and ctx.get_workplace_buffer_over_capacity_amount("neu_wood") == 30,
		"Review B.4: Full buffer (50/50) followed by reduction to 20 preserves all 50 units (30 excess)"
	)

	# Case 5: Deposit while over-capacity must be rejected
	var dep_over := ctx.deposit_to_workplace_buffer("neu_farm", 1)
	_assert(
		not bool(dep_over.get("ok", false))
		and wp_farm.buffer_amount == 40,
		"Review B.5: Deposit while over-capacity (40 / 20) is rejected and buffer remains 40"
	)

	# Case 6 & 7: Repeated reconciliation while over-capacity, then partial withdrawal
	ctx.reconcile_buildings(reduced_blds)
	_assert(wp_farm.buffer_amount == 40 and ctx.get_workplace_effective_buffer_capacity("neu_farm") == 20, "Review B.7: Repeated reconciliation while over-capacity preserves all 40 units")
	var w1 := ctx.withdraw_from_workplace_buffer("neu_farm", 15) # 40 -> 25 (still > 20)
	_assert(
		bool(w1.get("ok", false))
		and wp_farm.buffer_amount == 25
		and ctx.is_workplace_buffer_over_capacity("neu_farm")
		and ctx.get_workplace_buffer_over_capacity_amount("neu_farm") == 5,
		"Review B.6a: Partial withdrawal (40 -> 25) preserves 25 units and keeps 5 over-capacity"
	)

	# Case 8 & 9: Serialization while over-capacity (25 / 20 on neu_farm, 50 / 20 on neu_wood), restoration, and subsequent withdrawal
	var restored_ctx = SettlementVillagerContextScript.from_dict(ctx.to_dict())
	_assert(
		restored_ctx != null
		and restored_ctx.workplace_registry.get_workplace("neu_farm").buffer_amount == 25
		and restored_ctx.get_workplace_effective_buffer_capacity("neu_farm") == 20
		and restored_ctx.is_workplace_buffer_over_capacity("neu_farm")
		and not bool(restored_ctx.deposit_to_workplace_buffer("neu_farm", 1).get("ok", false)),
		"Review B.8: Serialization and restoration while over-capacity preserves exact buffer (25) and effective capacity (20)"
	)
	var w2 = restored_ctx.withdraw_from_workplace_buffer("neu_farm", 10) # 25 -> 15 (<= 20!)
	_assert(
		bool(w2.get("ok", false))
		and restored_ctx.workplace_registry.get_workplace("neu_farm").buffer_amount == 15
		and restored_ctx.workplace_registry.get_workplace("neu_farm").buffer_capacity == 20
		and not restored_ctx.is_workplace_buffer_over_capacity("neu_farm")
		and bool(restored_ctx.deposit_to_workplace_buffer("neu_farm", 5).get("ok", false))
		and not bool(restored_ctx.deposit_to_workplace_buffer("neu_farm", 1).get("ok", false)),
		"Review B.9: Subsequent withdrawal after restore (25 -> 15) returns buffer to normal capacity (20) and allows deposits up to 20"
	)

	# Also verify that removing a workplace with non-zero buffer preserves its buffer in salvaged_workplace_buffers
	var only_hq: Array[Dictionary] = [
		{"id": "neu_hq", "type": "townhall", "cell": Vector2i(39, 39), "size": Vector2i(3, 3), "role": "hq"}
	]
	restored_ctx.reconcile_buildings(only_hq)
	var salv: Dictionary = restored_ctx.get_salvaged_workplace_buffers()
	_assert(
		int(salv.get("neu_farm", {}).get("amount", 0)) == 20
		and int(salv.get("neu_wood", {}).get("amount", 0)) == 50,
		"Review B.10: Removing workplaces with non-zero buffers preserves 100% of their contents in salvaged_workplace_buffers"
	)

func _test_review_c_storage_capacity_provenance_and_lifecycle() -> void:
	print("\n[Review C] Storage Capacity Provenance, Lifecycle & Recovery Across All Six Variants")
	var variants: Array[Dictionary] = [
		{"sid": "stl_c_mil_f", "fid": "rival_military", "tier": "full", "init_food_cap": 500, "rec_food_cap": 1000, "bonus_food": 500},
		{"sid": "stl_c_mil_c", "fid": "rival_military", "tier": "compact", "init_food_cap": 500, "rec_food_cap": 500, "bonus_food": 0},
		{"sid": "stl_c_mer_f", "fid": "rival_merchant", "tier": "full", "init_food_cap": 500, "rec_food_cap": 1500, "bonus_food": 1000},
		{"sid": "stl_c_mer_c", "fid": "rival_merchant", "tier": "compact", "init_food_cap": 500, "rec_food_cap": 1000, "bonus_food": 500},
		{"sid": "stl_c_neu_f", "fid": "neutral_tribe", "tier": "full", "init_food_cap": 500, "rec_food_cap": 1000, "bonus_food": 500},
		{"sid": "stl_c_neu_c", "fid": "neutral_tribe", "tier": "compact", "init_food_cap": 500, "rec_food_cap": 1000, "bonus_food": 500}
	]

	for v_spec in variants:
		var sid: String = String(v_spec["sid"])
		var fid: String = String(v_spec["fid"])
		var tier: String = String(v_spec["tier"])
		var exp_init: int = int(v_spec["init_food_cap"])
		var exp_rec: int = int(v_spec["rec_food_cap"])
		var exp_bonus: int = int(v_spec["bonus_food"])

		var ctx := SettlementVillagerContextScript.new(sid, fid)
		var stl := _build_canonical_settlement(sid, fid, tier)
		var init_cap: int = ctx.economy.get_capacity("food")
		ctx.reconcile_buildings(stl)
		var cap_1: int = ctx.economy.get_capacity("food")
		ctx.reconcile_buildings(stl)
		var cap_2: int = ctx.economy.get_capacity("food")

		_assert(
			init_cap == exp_init
			and cap_1 == exp_rec
			and cap_2 == exp_rec
			and ctx.economy.get_base_capacity("food") == 500
			and ctx.economy.get_derived_capacity_bonus("food") == exp_bonus,
			"Review C (%s %s): init=%d, rec1=%d, rec2=%d, base=500, bonus=%d" % [fid, tier, init_cap, cap_1, cap_2, exp_bonus]
		)

	# Full lifecycle on Merchant Full: remove 1 storehouse (1500 -> 1000), stock preservation, over-capacity recovery, restore & rebuild
	var ctx_mer := SettlementVillagerContextScript.new("stl_mer_cap_life", "rival_merchant")
	var mer_full := _build_canonical_settlement("stl_mer_cap_life", "rival_merchant", "full")
	ctx_mer.reconcile_buildings(mer_full)
	ctx_mer.economy.credit_resource("food", 1100, "caravan_inflow", "bulk_food", 12) # 70 + 1100 = 1170 / 1500
	var without_store_2: Array[Dictionary] = []
	for b in mer_full.buildings:
		if String(b["id"]) != "mer_store_2":
			without_store_2.append((b as Dictionary).duplicate(true))
	ctx_mer.reconcile_buildings(without_store_2)
	_assert(
		ctx_mer.economy.get_capacity("food") == 1000
		and ctx_mer.economy.get_derived_capacity_bonus("food") == 500
		and ctx_mer.economy.get_resource("food") == 1170
		and ctx_mer.economy.is_over_capacity("food")
		and int(ctx_mer.economy.get_over_capacity_resources().get("food", 0)) == 170,
		"Review C.2: Removing 1 of 2 storehouses in Merchant Full lowers food cap 1500 -> 1000 and preserves all 1170 food (170 over-capacity)"
	)
	# Legitimate withdrawal (200 food) brings stock to 970 <= 1000 and clears over-capacity
	var deb_res: Dictionary = ctx_mer.economy.debit_resource("food", 200, "villager_rations", "consume_food", 18)
	_assert(
		bool(deb_res.get("ok", false))
		and ctx_mer.economy.get_resource("food") == 970
		and not ctx_mer.economy.is_over_capacity("food")
		and ctx_mer.economy.get_over_capacity_resources().is_empty(),
		"Review C.3: Legitimate withdrawal (1170 -> 970) clears over-capacity state at cap 1000"
	)
	# Serialize, restore, and rebuild full layout -> capacity returns to 1500
	var mer_restored = SettlementVillagerContextScript.from_dict(ctx_mer.to_dict())
	mer_restored.reconcile_buildings(mer_full)
	_assert(
		mer_restored.economy.get_capacity("food") == 1500
		and mer_restored.economy.get_derived_capacity_bonus("food") == 1000
		and mer_restored.economy.get_resource("food") == 970,
		"Review C.4: Restoring and rebuilding Merchant Full restores food capacity to 1500 while preserving stock 970"
	)

func _test_review_d_e_f_workplace_contract_replacement_and_quotas() -> void:
	print("\n[Reviews D, E & F] Workplace Field Contract, Building Replacement, Quota Changes & Market Non-Storage Rule")
	var ctx := SettlementVillagerContextScript.new("stl_rev_def", "neutral_tribe")
	var blds_initial: Array[Dictionary] = [
		{"id": "neu_hq", "type": "townhall", "cell": Vector2i(39, 39), "size": Vector2i(3, 3), "role": "hq"},
		{"id": "neu_wood", "type": "woodcutter", "cell": Vector2i(35, 39), "size": Vector2i(2, 2), "role": "production"}
	]
	for i in range(8):
		ctx.create_and_add_villager("Worker %d" % (i + 1), "idle", Vector2i(40, 40))

	ctx.reconcile_buildings(blds_initial)
	# 4 Woodcutter slots on neu_wood + 2 Hauler slots on neu_hq = 6 assigned, 2 idle
	var v1 = ctx.get_villager("npc_stl_rev_def_1")
	var j1 = ctx.job_board.get_job(v1.active_job_id)
	var wp1 = ctx.workplace_registry.get_workplace(v1.workplace_id)
	_assert(
		v1 != null and j1 != null and wp1 != null
		and v1.workplace_id == "neu_wood"
		and j1.workplace_id == "neu_wood"
		and wp1.workplace_id == "neu_wood"
		and wp1.building_id == "neu_wood"
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Review D.1: 4-way relationship (villager <-> job <-> workplace <-> building_id) is consistent"
	)

	# Review E (6.3): Replace 'neu_wood' with 'neu_wood_rebuilt' (same type 'woodcutter', different ID)
	var blds_replaced: Array[Dictionary] = [
		{"id": "neu_hq", "type": "townhall", "cell": Vector2i(39, 39), "size": Vector2i(3, 3), "role": "hq"},
		{"id": "neu_wood_rebuilt", "type": "woodcutter", "cell": Vector2i(35, 39), "size": Vector2i(2, 2), "role": "production"}
	]
	ctx.reconcile_buildings(blds_replaced)
	_assert(
		not ctx.workplace_registry.has_workplace("neu_wood")
		and ctx.workplace_registry.has_workplace("neu_wood_rebuilt")
		and v1.workplace_id == "neu_wood_rebuilt"
		and v1.active_job_id.find("neu_wood_rebuilt") >= 0
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Review E (6.3): Replacing building with same type and new ID ('neu_wood_rebuilt') removes old workplace/jobs and reconciles villagers cleanly"
	)

	# Review E (6.4): Worker quota changes (increase 4 -> 6, decrease 6 -> 2, zero 2 -> 0, disable, restore)
	ctx.set_workplace_quota("neu_wood_rebuilt", 6)
	_assert(
		int(ctx.verify_assignment_integrity().get("workers_per_workplace", {}).get("neu_wood_rebuilt", 0)) == 6
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Review E (6.4a): Increasing worker_quota from 4 to 6 assigns 6 villagers to 'neu_wood_rebuilt'"
	)

	ctx.set_workplace_quota("neu_wood_rebuilt", 2)
	_assert(
		int(ctx.verify_assignment_integrity().get("workers_per_workplace", {}).get("neu_wood_rebuilt", 0)) == 2
		and v1.workplace_id == "neu_wood_rebuilt"
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Review E (6.4b): Decreasing worker_quota from 6 to 2 preserves top 2 existing assignments and safely unassigns excess workers"
	)

	ctx.set_workplace_quota("neu_wood_rebuilt", 0)
	_assert(
		int(ctx.verify_assignment_integrity().get("workers_per_workplace", {}).get("neu_wood_rebuilt", 0)) == 0
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Review E (6.4c): Setting worker_quota to 0 unassigns all workers from 'neu_wood_rebuilt'"
	)

	ctx.set_workplace_quota("neu_wood_rebuilt", 4)
	ctx.set_workplace_active("neu_wood_rebuilt", false)
	_assert(
		int(ctx.verify_assignment_integrity().get("workers_per_workplace", {}).get("neu_wood_rebuilt", 0)) == 0
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Review E (6.4d): Disabling workplace ('is_active = false') unassigns all workers from 'neu_wood_rebuilt'"
	)

	ctx.set_workplace_active("neu_wood_rebuilt", true)
	_assert(
		int(ctx.verify_assignment_integrity().get("workers_per_workplace", {}).get("neu_wood_rebuilt", 0)) == 4
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Review E (6.4e): Re-enabling workplace ('is_active = true') restores 4 active job slots and assignments"
	)

	# Removing an assigned villager clears its job's assigned_villager_id immediately
	var assigned_jid_before_rem: String = v1.active_job_id
	ctx.remove_villager(v1.villager_id)
	_assert(
		ctx.job_board.get_job(assigned_jid_before_rem).assigned_villager_id == ""
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Review D.2: Removing an assigned villager immediately clears job.assigned_villager_id so no job references a missing villager"
	)

	# Review F.1: A Market without a separate Storehouse is NEVER silently treated as a final Storehouse
	var market_only_blds: Array[Dictionary] = [
		{"id": "mer_hq_alone", "type": "market", "cell": Vector2i(39, 39), "size": Vector2i(3, 3), "role": "hq"}
	]
	var d_mkt_alone := SettlementBuildingCapabilityAdapterScript.derive_capabilities_from_buildings("stl_mkt_alone", "rival_merchant", market_only_blds)
	_assert(
		bool(d_mkt_alone["ok"])
		and (d_mkt_alone["final_storage_ids"] as Array).is_empty()
		and not bool(d_mkt_alone["building_descriptors"][0]["is_dropoff"])
		and (d_mkt_alone["transport_routes"] as Array).is_empty(),
		"Review F.1: Market without a separate Storehouse is never treated as a final Storehouse (final_storage_ids is empty, is_dropoff=false)"
	)

func _test_final_audit_a_neutral_tribe_compact_workforce() -> void:
	print("\n[Final Audit A] Neutral Tribe Compact Workforce Feasibility (Populations 0..4, Conditional Hauler & Legacy Over-Capacity)")
	var neu_comp := _build_canonical_settlement("stl_neu_comp_fa", "neutral_tribe", "compact")
	var ctx := SettlementVillagerContextScript.new("stl_neu_comp_fa", "neutral_tribe")
	var rec0 := ctx.reconcile_buildings(neu_comp)
	var init_wood_stock: int = ctx.economy.get_resource("wood")

	# Scenario 1: Zero villagers
	_assert(
		bool(rec0["ok"])
		and ctx.get_housing_capacity() == 4
		and ctx.get_villager_count() == 0
		and ctx.job_board.get_job_count() == 3
		and int(rec0["assigned_villager_count"]) == 0
		and int(rec0["idle_villager_count"]) == 0,
		"Final Audit A.1 (Pop 0): Housing capacity == 4, 3 job slots (2 Woodcutter + 1 Hauler), 0 assigned, 0 idle"
	)

	# Scenario 2: One villager -> 1 Woodcutter (priority 7), 0 Hauler, 0 Idle
	var v1 = ctx.create_and_add_villager("Compact 1", "idle", Vector2i(40, 40))
	ctx.assign_villagers_to_jobs()
	_assert(
		v1.role == "woodcutter"
		and v1.workplace_id == "neutral_tribe_sec_1"
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Final Audit A.2 (Pop 1): 1 Woodcutter ('neutral_tribe_sec_1'), 0 Hauler, 0 Idle"
	)

	# Scenario 3a: Two villagers with empty output buffer (buffer_amount == 0) -> 2 Woodcutter, 0 Hauler, 0 Idle
	var v2 = ctx.create_and_add_villager("Compact 2", "idle", Vector2i(40, 40))
	ctx.assign_villagers_to_jobs()
	_assert(
		v1.role == "woodcutter"
		and v2.role == "woodcutter"
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Final Audit A.3a (Pop 2, buffer == 0): 2 Woodcutter, 0 Hauler, 0 Idle"
	)

	# Scenario 3b: Conditional Hauler at Pop 2 when output buffer has pending wood requiring transfer (buffer_amount > 0)
	ctx.deposit_to_workplace_buffer("neutral_tribe_sec_1", 12)
	ctx.assign_villagers_to_jobs()
	_assert(
		v1.role == "woodcutter"
		and v2.role == "hauler"
		and v2.workplace_id == "neutral_tribe_hq"
		and ctx.workplace_registry.get_workplace("neutral_tribe_sec_1").buffer_amount == 12
		and ctx.economy.get_resource("wood") == init_wood_stock
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Final Audit A.3b (Pop 2, buffer > 0): Conditional Hauler rule reserves 1 Hauler to Townhall + 1 Woodcutter without executing transfer"
	)
	# Drain buffer back to 0 for standard progression check
	ctx.withdraw_from_workplace_buffer("neutral_tribe_sec_1", 12)

	# Scenario 4: Three villagers -> 2 Woodcutter, 1 Hauler to Townhall, 0 Idle
	var v3 = ctx.create_and_add_villager("Compact 3", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(neu_comp)
	var roles_at_3: Dictionary = {"woodcutter": 0, "hauler": 0, "idle": 0}
	for v in ctx.get_all_villagers():
		roles_at_3[v.role] = int(roles_at_3.get(v.role, 0)) + 1
	_assert(
		int(roles_at_3["woodcutter"]) == 2
		and int(roles_at_3["hauler"]) == 1
		and int(roles_at_3["idle"]) == 0
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Final Audit A.4 (Pop 3): 2 Woodcutter, 1 Hauler to Townhall, 0 Idle"
	)

	# Scenario 5: Four villagers at full compact housing capacity (4) -> 2 Woodcutter, 1 Hauler to Townhall, 1 Idle
	var v4 = ctx.create_and_add_villager("Compact 4", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(neu_comp)
	var roles_at_4: Dictionary = {"woodcutter": 0, "hauler": 0, "idle": 0}
	for v in ctx.get_all_villagers():
		roles_at_4[v.role] = int(roles_at_4.get(v.role, 0)) + 1
	_assert(
		ctx.is_at_housing_capacity()
		and ctx.get_available_housing_slots() == 0
		and int(roles_at_4["woodcutter"]) == 2
		and int(roles_at_4["hauler"]) == 1
		and int(roles_at_4["idle"]) == 1
		and v4.role == "idle"
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Final Audit A.5 (Pop 4 at full housing capacity): 2 Woodcutter, 1 Hauler to Townhall, 1 Idle"
	)

	# Scenario 6: Legacy settlement with population exceeding housing capacity (5 > 4)
	var v5 = ctx.create_and_add_villager("Compact 5 (Legacy Over-Cap)", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(neu_comp)
	var roles_at_5: Dictionary = {"woodcutter": 0, "hauler": 0, "idle": 0}
	for v in ctx.get_all_villagers():
		roles_at_5[v.role] = int(roles_at_5.get(v.role, 0)) + 1
	_assert(
		ctx.get_villager_count() == 5
		and ctx.get_housing_capacity() == 4
		and ctx.get_available_housing_slots() == 0
		and int(roles_at_5["woodcutter"]) == 2
		and int(roles_at_5["hauler"]) == 1
		and int(roles_at_5["idle"]) == 2
		and v5.role == "idle"
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Final Audit A.6 (Pop 5 > 4 legacy over-capacity): Preserves all 5 villagers (2 Woodcutter, 1 Hauler, 2 Idle)"
	)

	# Scenario 7: Repeated assignment with identical inputs is 100% deterministic
	var snap_before_rep: Dictionary = ctx.to_dict()
	for _i in range(4):
		ctx.assign_villagers_to_jobs()
		ctx.reconcile_buildings(neu_comp)
	_assert(
		ctx.to_dict() == snap_before_rep
		and ctx.economy.get_resource("wood") == init_wood_stock,
		"Final Audit A.7: Repeated assignment and reconciliation with identical inputs is 100% deterministic and transfers 0 resources"
	)

func _test_final_audit_b_military_full_guard_patrol() -> void:
	print("\n[Final Audit B] Military Full Guard Patrol Capability & Watchtower Target Reconciliation")
	var mil_full := _build_canonical_settlement("stl_mil_full_fb", "rival_military", "full")
	var ctx := SettlementVillagerContextScript.new("stl_mil_full_fb", "rival_military")

	var g1 = ctx.create_and_add_villager("Guard 1", "idle", Vector2i(40, 40))
	var g2 = ctx.create_and_add_villager("Guard 2", "idle", Vector2i(40, 40))
	var h1 = ctx.create_and_add_villager("Hauler 1", "idle", Vector2i(40, 40))
	var h2 = ctx.create_and_add_villager("Hauler 2", "idle", Vector2i(40, 40))

	var rec := ctx.reconcile_buildings(mil_full)
	var expected_towers: Array[String] = ["mil_tower_nw", "mil_tower_ne", "mil_tower_se", "mil_tower_sw"]

	# 1 & 2: Four Watchtower targets in deterministic order
	_assert(
		bool(rec["ok"]) and ctx.get_patrol_target_ids() == expected_towers,
		"Final Audit B.1: Military Full exposes 4 Watchtower patrol targets in deterministic order ['mil_tower_nw', 'mil_tower_ne', 'mil_tower_se', 'mil_tower_sw']"
	)

	# 3: All patrol targets belong to the same settlement and have 0 worker quota (no extra Guard jobs created)
	var all_same_sid: bool = true
	for pt in ctx.get_patrol_targets():
		if String(pt.get("settlement_id", "")) != "stl_mil_full_fb" or String(pt.get("building_type", "")) != "watchtower":
			all_same_sid = false
	var guard_job_count: int = 0
	for j in ctx.job_board.get_all_jobs():
		if j.job_type == "guard":
			guard_job_count += 1
	_assert(
		all_same_sid and guard_job_count == 2 and ctx.job_board.get_job_count() == 4,
		"Final Audit B.2: All 4 Watchtower targets belong to 'stl_mil_full_fb' and generate 0 extra Guard jobs (exact 2 Guard jobs on 'mil_hq')"
	)

	# Guard jobs & assigned Guard villagers link to owning Barracks 'mil_hq' and deterministic initial Watchtower targets
	var gp_1: Dictionary = ctx.get_guard_patrol_for_job(g1.active_job_id)
	var gp_2: Dictionary = ctx.get_guard_patrol_for_job(g2.active_job_id)
	_assert(
		bool(gp_1.get("ok", false))
		and bool(gp_2.get("ok", false))
		and String(gp_1["barracks_building_id"]) == "mil_hq"
		and g1.workplace_id == "mil_hq"
		and g2.workplace_id == "mil_hq"
		and g1.work_target_id == "mil_tower_nw"
		and g2.work_target_id == "mil_tower_ne",
		"Final Audit B.3: Guard jobs identify owning Barracks 'mil_hq' and assign deterministic initial patrol targets ('mil_tower_nw', 'mil_tower_ne')"
	)

	# Deterministic patrol cycle & missing Watchtower target fallback
	var n1: Dictionary = ctx.get_next_patrol_target("mil_tower_nw", "mil_hq")
	var n2: Dictionary = ctx.get_next_patrol_target("mil_tower_ne", "mil_hq")
	var n3: Dictionary = ctx.get_next_patrol_target("mil_tower_se", "mil_hq")
	var n4: Dictionary = ctx.get_next_patrol_target("mil_tower_sw", "mil_hq")
	var n_missing: Dictionary = ctx.get_next_patrol_target("non_existent_tower_99", "mil_hq")
	_assert(
		String(n1.get("building_id", "")) == "mil_tower_ne"
		and String(n2.get("building_id", "")) == "mil_tower_se"
		and String(n3.get("building_id", "")) == "mil_tower_sw"
		and String(n4.get("building_id", "")) == "mil_tower_nw"
		and bool(n_missing.get("ok", false))
		and bool(n_missing.get("recovered_from_missing_target", false))
		and String(n_missing.get("building_id", "")) == "mil_tower_nw",
		"Final Audit B.4: Patrol cycle order is deterministic and missing Watchtower target safely recovers to 'mil_tower_nw'"
	)

	# 5: One Watchtower removed ('mil_tower_ne' removed)
	var blds_minus_ne: Array[Dictionary] = []
	for b in mil_full.buildings:
		if String(b["id"]) != "mil_tower_ne":
			blds_minus_ne.append((b as Dictionary).duplicate(true))
	ctx.reconcile_buildings(blds_minus_ne)
	_assert(
		ctx.get_patrol_target_ids() == ["mil_tower_nw", "mil_tower_se", "mil_tower_sw"]
		and g1.work_target_id == "mil_tower_nw"
		and g2.work_target_id == "mil_tower_se",
		"Final Audit B.5: Removing 'mil_tower_ne' updates patrol target list to 3 towers and reconciles Guard 2 target to 'mil_tower_se'"
	)

	# 6: One Watchtower replaced by a new ID ('mil_tower_sw' -> 'mil_tower_sw_rebuilt')
	var blds_replaced_sw: Array[Dictionary] = []
	for b in blds_minus_ne:
		var b_copy: Dictionary = (b as Dictionary).duplicate(true)
		if String(b_copy["id"]) == "mil_tower_sw":
			b_copy["id"] = "mil_tower_sw_rebuilt"
		blds_replaced_sw.append(b_copy)
	ctx.reconcile_buildings(blds_replaced_sw)
	_assert(
		ctx.get_patrol_target_ids() == ["mil_tower_nw", "mil_tower_se", "mil_tower_sw_rebuilt"]
		and not ctx.get_patrol_target_ids().has("mil_tower_sw"),
		"Final Audit B.6: Replacing 'mil_tower_sw' with 'mil_tower_sw_rebuilt' removes old ID and registers new patrol target ID"
	)

	# 7: Repeated reconciliation and Serialization/Restoration of patrol descriptors
	var snap_patrol: Dictionary = ctx.to_dict()
	ctx.reconcile_buildings(blds_replaced_sw)
	var restored_ctx = SettlementVillagerContextScript.from_dict(snap_patrol)
	_assert(
		ctx.to_dict() == snap_patrol
		and restored_ctx != null
		and restored_ctx.get_patrol_target_ids() == ["mil_tower_nw", "mil_tower_se", "mil_tower_sw_rebuilt"]
		and restored_ctx.get_guard_patrol_descriptors().size() == 1,
		"Final Audit B.7: Repeated reconciliation and serialization/restoration preserve exact Guard patrol descriptors"
	)

	# 8: All Watchtowers removed -> 2 Guard jobs on Barracks remain valid with Barracks fallback target
	var blds_no_towers: Array[Dictionary] = []
	for b in mil_full.buildings:
		if String(b["type"]) != "watchtower":
			blds_no_towers.append((b as Dictionary).duplicate(true))
	ctx.reconcile_buildings(blds_no_towers)
	var fallback_next: Dictionary = ctx.get_next_patrol_target("mil_tower_nw", "mil_hq")
	_assert(
		ctx.get_patrol_target_ids().is_empty()
		and g1.role == "guard" and g2.role == "guard"
		and g1.work_target_id == "mil_hq" and g2.work_target_id == "mil_hq"
		and bool(fallback_next.get("is_barracks_fallback", false))
		and String(fallback_next.get("building_id", "")) == "mil_hq"
		and bool(ctx.verify_assignment_integrity().get("ok", false)),
		"Final Audit B.8: Removing all Watchtowers keeps both Guard jobs valid on 'mil_hq' with Barracks fallback target"
	)

	# 9: Military Compact retains its 2 Guard jobs on 'rival_military_hq' and only its 1 canonical Watchtower ('rival_military_sec_1')
	var mil_comp := _build_canonical_settlement("stl_mil_comp_fb", "rival_military", "compact")
	var ctx_mc := SettlementVillagerContextScript.new("stl_mil_comp_fb", "rival_military")
	ctx_mc.reconcile_buildings(mil_comp)
	_assert(
		ctx_mc.job_board.get_job_count() == 2
		and ctx_mc.get_patrol_target_ids() == ["rival_military_sec_1"],
		"Final Audit B.9: Military Compact retains 2 Guard jobs on 'rival_military_hq' and only its actual Watchtower 'rival_military_sec_1'"
	)

