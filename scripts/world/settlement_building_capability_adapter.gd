class_name SettlementBuildingCapabilityAdapter
extends RefCounted
## Derives functional building capabilities, housing capacity, storage capacity bonuses,
## workplace registrations, transport routes, deterministic job slots, and initial villager
## job assignments from canonical `SettlementData.buildings` (Architecture v1.0 — Phase 3).
##
## Strictly isolated from:
## - Player `WorldData.buildings` and `WorldData.buildings_by_cell`
## - Player `JobManager`, `WorkplaceManager`, `CitizenController`, and `/root/ResourceManager`
## - `FactionData.population` and `FactionData.resources`

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementJobBoardScript = preload("res://scripts/world/settlement_job_board.gd")
const SettlementWorkplaceRegistryScript = preload("res://scripts/world/settlement_workplace_registry.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

# Capability Identifiers
const CAP_HQ: String = "hq"
const CAP_RESIDENTIAL: String = "residential"
const CAP_RESIDENTIAL_HQ_BASELINE: String = "residential_hq_baseline"
const CAP_WORKPLACE: String = "workplace"
const CAP_MILITARY_GUARD: String = "military_guard"
const CAP_FOOD_PRODUCTION: String = "food_production"
const CAP_WOOD_PRODUCTION: String = "wood_production"
const CAP_SMITH_RESTRICTED: String = "smith_restricted"
const CAP_MARKET_RECEIVING: String = "market_receiving"
const CAP_RECEIVING_BUFFER: String = "receiving_buffer"
const CAP_OUTPUT_BUFFER: String = "output_buffer"
const CAP_FINAL_STORAGE: String = "final_storage"
const CAP_RESOURCE_STORAGE: String = "resource_storage"
const CAP_TRANSPORT_SOURCE: String = "transport_source"
const CAP_TRANSPORT_DESTINATION: String = "transport_destination"
const CAP_DEFENSE_STATIC: String = "defense_static"
const CAP_PATROL_WAYPOINT: String = "patrol_waypoint"
const CAP_WALL_STATIC: String = "wall_static"
const CAP_UNSUPPORTED: String = "unsupported_non_functional"

# Locked Housing Constants (Section 6)
# Per-house capacity is sourced from EconomyConfig.get_house_capacity(1) == 6.
# Compact Market/Townhall HQ baseline when 0 houses exist is 4 (never applied to Military Compact).
const COMPACT_HQ_HOUSING_BASELINE: int = 4
const COMPACT_HQ_BASELINE_TYPES: Array[String] = ["market", "townhall"]

# Provisional Phase 3 Tuning Constants (Centralized & Documented per Review C & Final Audit Review A)
# 1. Full Townhall final-storage Hauler quota (when house_count > 0 and >= 1 validated incoming route exists): 2.
const PROVISIONAL_TOWNHALL_HAULER_QUOTA: int = 2
# 2. Compact Townhall final-storage Hauler quota (when house_count == 0, housing capacity == 4): 1.
const PROVISIONAL_COMPACT_TOWNHALL_HAULER_QUOTA: int = 1
# 3. Compact Woodcutter quota (when house_count == 0 and role == "support" in Neutral Tribe Compact): 2,
#    leaving workforce capacity at compact housing cap (4) for 2 Woodcutter, 1 conditional Hauler to Townhall, and 1 Idle.
const PROVISIONAL_COMPACT_WOODCUTTER_QUOTA: int = 2

# Default Workplace Buffer Capacities
# Grounded in WorkplaceManager.WorkplaceData.buffer_capacity (50) and EconomyConfig workshop recipe buffer_capacity (40).
const DEFAULT_BUFFER_CAPACITY: int = 50
const WORKSHOP_BUFFER_CAPACITY: int = 40

# Deterministic Job Priorities (used for initial assignment ordering before job_id tie-break)
const PRIORITY_GUARD: int = 10
const PRIORITY_HUNTER: int = 9
const PRIORITY_FARMER: int = 8
const PRIORITY_WOODCUTTER: int = 7
const PRIORITY_HAULER: int = 6
const PRIORITY_SMITH: int = 5

const DEFAULT_WORK_HOURS_BY_ROLE: Dictionary = {
	SettlementVillagerDataScript.ROLE_GUARD: 4.0,
	SettlementVillagerDataScript.ROLE_HUNTER: 2.5,
	SettlementVillagerDataScript.ROLE_FARMER: 3.0,
	SettlementVillagerDataScript.ROLE_WOODCUTTER: 3.0,
	SettlementVillagerDataScript.ROLE_HAULER: 2.0,
	SettlementVillagerDataScript.ROLE_SMITH: 3.0
}

## Formats a deterministic, collision-safe job ID using double-underscore delimiters (`__`)
## so settlement IDs and workplace IDs containing single underscores can never collide.
static func format_deterministic_job_id(
	p_settlement_id: String,
	p_workplace_id: String,
	p_job_type: String,
	p_slot_index: int
) -> String:
	if not SettlementVillagerDataScript.is_valid_identifier(p_settlement_id):
		return ""
	if not SettlementVillagerDataScript.is_valid_identifier(p_workplace_id):
		return ""
	if not SettlementVillagerDataScript.is_valid_identifier(p_job_type):
		return ""
	if p_slot_index < 1:
		return ""
	return "job__%s__%s__%s__%d" % [p_settlement_id, p_workplace_id, p_job_type, p_slot_index]

## Parses a deterministic Phase 3 job ID (`job__<sid>__<wpid>__<job_type>__<slot>`).
## Returns `{}` if `p_job_id` does not follow the deterministic format.
static func parse_deterministic_job_id(p_job_id: String) -> Dictionary:
	if not p_job_id.begins_with("job__"):
		return {}
	var parts: PackedStringArray = p_job_id.split("__")
	if parts.size() != 5:
		return {}
	var slot_str: String = parts[4]
	if not slot_str.is_valid_int() or int(slot_str) < 1:
		return {}
	return {
		"settlement_id": String(parts[1]),
		"workplace_id": String(parts[2]),
		"job_type": String(parts[3]),
		"slot_index": int(slot_str)
	}

## Computes the deterministic perimeter access cell for a building footprint (south-center entrance).
static func compute_access_cell(origin_cell: Vector2i, size: Vector2i) -> Vector2i:
	var sx: int = maxi(1, size.x)
	var sy: int = maxi(1, size.y)
	return Vector2i(origin_cell.x + int(sx / 2), origin_cell.y + sy)

## Validates a single raw building dictionary from `SettlementData.buildings`.
static func validate_building_record(b: Variant, expected_settlement_id: String = "") -> Dictionary:
	if not (b is Dictionary):
		return {"ok": false, "reason": "not_a_dictionary"}
	var d: Dictionary = b
	if not (d.get("id") is String) or not (d.get("type") is String):
		return {"ok": false, "reason": "missing_id_or_type"}
	var bid := String(d["id"]).strip_edges()
	var btype := String(d["type"]).strip_edges()
	if not SettlementVillagerDataScript.is_valid_identifier(bid):
		return {"ok": false, "reason": "invalid_building_id"}
	if not SettlementVillagerDataScript.is_valid_identifier(btype):
		return {"ok": false, "reason": "invalid_building_type"}
	if d.has("settlement_id"):
		if not (d["settlement_id"] is String):
			return {"ok": false, "reason": "invalid_building_settlement_id"}
		var b_sid := String(d["settlement_id"]).strip_edges()
		if not expected_settlement_id.is_empty() and b_sid != expected_settlement_id:
			return {"ok": false, "reason": "cross_settlement_building"}
	if not d.has("cell") or not SettlementVillagerDataScript._is_valid_vec2i_input(d["cell"]):
		return {"ok": false, "reason": "invalid_cell"}
	var cell: Vector2i = SettlementVillagerDataScript._parse_vec2i(d["cell"], Vector2i(-1, -1))
	var size: Vector2i = Vector2i.ONE
	if d.has("size"):
		if not SettlementVillagerDataScript._is_valid_vec2i_input(d["size"]):
			return {"ok": false, "reason": "invalid_size"}
		size = SettlementVillagerDataScript._parse_vec2i(d["size"], Vector2i.ZERO)
	else:
		var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get(btype, {})
		size = bp.get("footprint", Vector2i.ONE)
	if size.x <= 0 or size.y <= 0:
		return {"ok": false, "reason": "non_positive_size"}

	var level_val: int = 1
	if d.has("level"):
		if not SettlementEconomyScript._is_valid_strict_int(d["level"]) or int(d["level"]) < 1 or int(d["level"]) > EconomyConfigScript.MAX_BUILDING_LEVEL:
			return {"ok": false, "reason": "invalid_building_level"}
		level_val = int(d["level"])

	var quota_override: int = -1
	if d.has("worker_quota"):
		if not SettlementEconomyScript._is_valid_strict_int(d["worker_quota"]) or int(d["worker_quota"]) < 0:
			return {"ok": false, "reason": "invalid_worker_quota_override"}
		quota_override = int(d["worker_quota"])

	var buffer_cap_override: int = -1
	if d.has("buffer_capacity"):
		if not SettlementEconomyScript._is_valid_strict_int(d["buffer_capacity"]) or int(d["buffer_capacity"]) < 0:
			return {"ok": false, "reason": "invalid_buffer_capacity_override"}
		buffer_cap_override = int(d["buffer_capacity"])

	var is_active_override: bool = true
	var has_active_override: bool = false
	if d.has("is_active"):
		if not (d["is_active"] is bool):
			return {"ok": false, "reason": "invalid_is_active_override"}
		is_active_override = bool(d["is_active"])
		has_active_override = true

	var role_str: String = String(d.get("role", "")).strip_edges() if (d.get("role", "") is String) else ""
	var blocking_val: bool = bool(d.get("blocking", true)) if (d.get("blocking", true) is bool) else true
	return {
		"ok": true,
		"id": bid,
		"type": btype,
		"cell": cell,
		"size": size,
		"level": level_val,
		"role": role_str,
		"blocking": blocking_val,
		"worker_quota_override": quota_override,
		"buffer_capacity_override": buffer_cap_override,
		"has_active_override": has_active_override,
		"is_active_override": is_active_override
	}

## Calculates housing capacity deterministically from a `buildings` Array.
## Malformed or duplicate building records are ignored so they never inflate housing capacity.
static func calculate_housing_capacity(buildings: Variant, _origin_faction_id: String = "") -> int:
	if not (buildings is Array):
		return 0
	var raw_list: Array = buildings
	var seen_ids: Dictionary = {}
	var seen_house_cells: Dictionary = {}
	var house_count: int = 0
	var total_house_capacity: int = 0
	var has_compact_baseline_hq: bool = false

	for item in raw_list:
		var v := validate_building_record(item)
		if not bool(v.get("ok", false)):
			continue
		var bid: String = String(v["id"])
		if seen_ids.has(bid):
			continue
		seen_ids[bid] = true
		var btype: String = String(v["type"])
		var bcell: Vector2i = v["cell"]
		var blvl: int = int(v.get("level", 1))
		if btype == "house":
			if seen_house_cells.has(bcell):
				continue
			seen_house_cells[bcell] = true
			house_count += 1
			total_house_capacity += EconomyConfigScript.get_house_capacity(blvl)
		elif COMPACT_HQ_BASELINE_TYPES.has(btype):
			has_compact_baseline_hq = true

	if house_count > 0:
		return total_house_capacity
	if has_compact_baseline_hq:
		return COMPACT_HQ_HOUSING_BASELINE
	return 0

## Validates a transport route candidate before any Hauler job or route descriptor is created.
static func validate_transport_route(
	p_settlement_id: String,
	source_descriptor: Variant,
	dest_descriptor: Variant,
	cargo_resource: String
) -> Dictionary:
	if not SettlementVillagerDataScript.is_valid_identifier(p_settlement_id):
		return {"ok": false, "reason": "invalid_settlement_id"}
	if not (source_descriptor is Dictionary) or not (dest_descriptor is Dictionary):
		return {"ok": false, "reason": "missing_source_or_dest"}
	var src: Dictionary = source_descriptor
	var dst: Dictionary = dest_descriptor
	var src_id: String = String(src.get("building_id", "")).strip_edges()
	var dst_id: String = String(dst.get("building_id", "")).strip_edges()
	if not SettlementVillagerDataScript.is_valid_identifier(src_id) or not SettlementVillagerDataScript.is_valid_identifier(dst_id):
		return {"ok": false, "reason": "empty_or_invalid_building_id"}
	if src_id == dst_id:
		return {"ok": false, "reason": "same_source_and_destination"}
	if String(src.get("settlement_id", "")) != p_settlement_id or String(dst.get("settlement_id", "")) != p_settlement_id:
		return {"ok": false, "reason": "cross_settlement_route"}
	if not bool(src.get("is_active", true)):
		return {"ok": false, "reason": "inactive_source_workplace"}
	if not bool(dst.get("is_active", true)):
		return {"ok": false, "reason": "inactive_dest_workplace"}
	if int(src.get("buffer_capacity", 0)) <= 0:
		return {"ok": false, "reason": "source_lacks_buffer_capacity"}
	if bool(src.get("is_dropoff", false)):
		return {"ok": false, "reason": "source_is_final_storage"}
	var src_caps: Array = src.get("capabilities", [])
	var dst_caps: Array = dst.get("capabilities", [])
	if not (src_caps.has(CAP_RECEIVING_BUFFER) or src_caps.has(CAP_OUTPUT_BUFFER) or src_caps.has(CAP_TRANSPORT_SOURCE)):
		return {"ok": false, "reason": "source_lacks_buffer_capability"}
	if not (dst_caps.has(CAP_FINAL_STORAGE) or dst_caps.has(CAP_TRANSPORT_DESTINATION)):
		return {"ok": false, "reason": "dest_lacks_final_storage_capability"}
	var clean_res: String = cargo_resource.strip_edges()
	if clean_res.is_empty() or not EconomyConfigScript.ALL_RESOURCES.has(clean_res) or clean_res == EconomyConfigScript.RES_GOLD:
		return {"ok": false, "reason": "unsupported_transport_resource"}
	var supported_src_res: Array = src.get("buffer_resources", [])
	if supported_src_res.is_empty() or not supported_src_res.has(clean_res):
		return {"ok": false, "reason": "resource_incompatible_with_source"}
	var dst_worker_cap: int = int(dst.get("hauler_worker_capacity", 0))
	if dst_worker_cap <= 0:
		return {"ok": false, "reason": "non_positive_worker_capacity"}
	var src_cell: Vector2i = src.get("access_cell", Vector2i(-1, -1))
	var dst_cell: Vector2i = dst.get("access_cell", Vector2i(-1, -1))
	if src_cell == dst_cell:
		return {"ok": false, "reason": "identical_access_cells"}

	return {
		"ok": true,
		"route_id": "route__%s__%s__to__%s" % [p_settlement_id, src_id, dst_id],
		"settlement_id": p_settlement_id,
		"source_building_id": src_id,
		"source_workplace_id": src_id,
		"source_cell": src_cell,
		"dest_building_id": dst_id,
		"dest_workplace_id": dst_id,
		"dest_cell": dst_cell,
		"cargo_resource": clean_res,
		"worker_slots": dst_worker_cap
	}

## Pure capability derivation from canonical `buildings` array for a settlement.
## If `strict_reject_malformed` is true, returns `ok: false` if any element in `buildings` is malformed.
static func derive_capabilities_from_buildings(
	p_settlement_id: String,
	p_origin_faction_id: String,
	buildings: Variant,
	economy: RefCounted = null,
	strict_reject_malformed: bool = true,
	enable_hunter: bool = false
) -> Dictionary:
	if not SettlementVillagerDataScript.is_valid_identifier(p_settlement_id):
		return {"ok": false, "reason": "invalid_settlement_id"}
	if not SettlementVillagerDataScript.is_valid_identifier(p_origin_faction_id):
		return {"ok": false, "reason": "invalid_origin_faction_id"}
	if not (buildings is Array):
		return {"ok": false, "reason": "buildings_not_an_array"}

	var raw_list: Array = buildings
	var validated_buildings: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	var seen_house_cells: Dictionary = {}
	var ignored_duplicate_ids: Array[String] = []

	for item in raw_list:
		var v := validate_building_record(item, p_settlement_id)
		if not bool(v.get("ok", false)):
			if strict_reject_malformed:
				return {"ok": false, "reason": String(v.get("reason", "malformed_building"))}
			continue
		var bid: String = String(v["id"])
		if seen_ids.has(bid):
			ignored_duplicate_ids.append(bid)
			continue
		if String(v["type"]) == "house":
			var hcell: Vector2i = v["cell"]
			if seen_house_cells.has(hcell):
				ignored_duplicate_ids.append(bid)
				continue
			seen_house_cells[hcell] = true
		seen_ids[bid] = true
		validated_buildings.append(v)

	# First pass: inspect composition (houses, storehouses, HQs)
	var house_count: int = 0
	var storehouse_ids: Array[String] = []
	var hq_building_id: String = ""

	for b in validated_buildings:
		var btype: String = String(b["type"])
		var bid: String = String(b["id"])
		if btype == "house":
			house_count += 1
		elif btype == "storehouse":
			storehouse_ids.append(bid)
		if btype in ["barracks", "market", "townhall"] and hq_building_id.is_empty():
			hq_building_id = bid

	var has_separate_storehouse: bool = not storehouse_ids.is_empty()

	# Determine sustainable Ore availability for Workshop / Smith restriction (Section 11)
	var smith_allowed: bool = false
	if economy != null and bool(economy.get("merchant_smith_enabled")) and int(economy.get_resource(EconomyConfigScript.RES_ORE)) >= 2:
		smith_allowed = true

	# Compute derived storage capacities starting from EconomyConfig.BASE_CAPACITIES (added once)
	var derived_capacities: Dictionary = {}
	var derived_capacity_bonuses: Dictionary = {}
	for res_id in EconomyConfigScript.ALL_RESOURCES:
		if res_id != EconomyConfigScript.RES_GOLD:
			derived_capacities[res_id] = int(EconomyConfigScript.BASE_CAPACITIES.get(res_id, 500))
			derived_capacity_bonuses[res_id] = 0

	var building_descriptors: Array[Dictionary] = []
	var descriptors_by_id: Dictionary = {}
	var residential_buildings: Array[Dictionary] = []
	var final_storage_ids: Array[String] = []
	var receiving_buffer_ids: Array[String] = []
	var output_buffer_ids: Array[String] = []
	var patrol_target_ids: Array[String] = []
	var patrol_targets: Array[Dictionary] = []
	var total_housing_capacity: int = 0

	for b in validated_buildings:
		var bid: String = String(b["id"])
		var btype: String = String(b["type"])
		var bcell: Vector2i = b["cell"]
		var bsize: Vector2i = b["size"]
		var blvl: int = int(b.get("level", 1))
		var access_c: Vector2i = compute_access_cell(bcell, bsize)
		var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get(btype, {})
		var q_override: int = int(b.get("worker_quota_override", -1))
		var buf_override: int = int(b.get("buffer_capacity_override", -1))
		var has_act_override: bool = bool(b.get("has_active_override", false))
		var act_override: bool = bool(b.get("is_active_override", true))

		var caps: Array[String] = []
		var housing_contrib: int = 0
		var storage_contrib: Dictionary = {}
		var is_workplace: bool = false
		var wp_job_type: String = ""
		var wp_quota: int = 0
		var wp_output_res: String = ""
		var wp_buffer_cap: int = 0
		var wp_is_dropoff: bool = false
		var wp_is_active: bool = act_override if has_act_override else true
		var buffer_resources: Array[String] = []
		var hauler_worker_cap: int = 0

		if String(b["role"]) == "hq" or bid == hq_building_id:
			caps.append(CAP_HQ)

		match btype:
			"house":
				caps.append(CAP_RESIDENTIAL)
				housing_contrib = EconomyConfigScript.get_house_capacity(blvl)
				total_housing_capacity += housing_contrib
				residential_buildings.append({"building_id": bid, "capacity": housing_contrib})

			"storehouse":
				caps.append(CAP_FINAL_STORAGE)
				caps.append(CAP_RESOURCE_STORAGE)
				caps.append(CAP_TRANSPORT_DESTINATION)
				storage_contrib = EconomyConfigScript.get_building_storage_bonus("storehouse", blvl)
				for r_key in storage_contrib.keys():
					if derived_capacities.has(r_key):
						var add_b: int = int(storage_contrib[r_key])
						derived_capacity_bonuses[r_key] = int(derived_capacity_bonuses[r_key]) + add_b
						derived_capacities[r_key] = int(derived_capacities[r_key]) + add_b
				is_workplace = true
				wp_job_type = SettlementVillagerDataScript.ROLE_HAULER
				hauler_worker_cap = q_override if q_override >= 0 else int(bp.get("max_workers", 2))
				wp_quota = 0 # Promoted to hauler_worker_cap in second pass only if a valid distinct source buffer exists
				wp_buffer_cap = buf_override if buf_override >= 0 else DEFAULT_BUFFER_CAPACITY
				wp_is_dropoff = true
				final_storage_ids.append(bid)

			"townhall":
				caps.append(CAP_RESOURCE_STORAGE)
				storage_contrib = EconomyConfigScript.get_building_storage_bonus("townhall", blvl)
				for r_key in storage_contrib.keys():
					if derived_capacities.has(r_key):
						var add_t: int = int(storage_contrib[r_key])
						derived_capacity_bonuses[r_key] = int(derived_capacity_bonuses[r_key]) + add_t
						derived_capacities[r_key] = int(derived_capacities[r_key]) + add_t
				if house_count == 0:
					caps.append(CAP_RESIDENTIAL_HQ_BASELINE)
					housing_contrib = COMPACT_HQ_HOUSING_BASELINE
					total_housing_capacity += housing_contrib
					residential_buildings.append({"building_id": bid, "capacity": housing_contrib})
				if not has_separate_storehouse:
					caps.append(CAP_FINAL_STORAGE)
					caps.append(CAP_TRANSPORT_DESTINATION)
					is_workplace = true
					wp_job_type = SettlementVillagerDataScript.ROLE_HAULER
					var default_th_hauler: int = PROVISIONAL_COMPACT_TOWNHALL_HAULER_QUOTA if house_count == 0 else PROVISIONAL_TOWNHALL_HAULER_QUOTA
					hauler_worker_cap = q_override if q_override >= 0 else default_th_hauler
					wp_quota = 0 # Promoted to hauler_worker_cap in second pass only if a valid distinct source buffer exists
					wp_buffer_cap = buf_override if buf_override >= 0 else DEFAULT_BUFFER_CAPACITY
					wp_is_dropoff = true
					final_storage_ids.append(bid)

			"barracks":
				caps.append(CAP_WORKPLACE)
				caps.append(CAP_MILITARY_GUARD)
				is_workplace = true
				wp_job_type = SettlementVillagerDataScript.ROLE_GUARD
				wp_quota = q_override if q_override >= 0 else int(bp.get("max_workers", 2))
				wp_buffer_cap = buf_override if buf_override >= 0 else DEFAULT_BUFFER_CAPACITY
				if has_separate_storehouse:
					# Military Full: Barracks acts as receiving buffer for external military rations
					if wp_is_active and wp_buffer_cap > 0:
						caps.append(CAP_RECEIVING_BUFFER)
						caps.append(CAP_TRANSPORT_SOURCE)
						wp_output_res = EconomyConfigScript.RES_FOOD
						buffer_resources = [EconomyConfigScript.RES_FOOD]
						receiving_buffer_ids.append(bid)
					wp_is_dropoff = false
				else:
					# Military Compact fallback: Barracks serves as final storage destination
					caps.append(CAP_FINAL_STORAGE)
					wp_output_res = ""
					wp_is_dropoff = true
					final_storage_ids.append(bid)

			"market":
				caps.append(CAP_MARKET_RECEIVING)
				if house_count == 0:
					caps.append(CAP_RESIDENTIAL_HQ_BASELINE)
					housing_contrib = COMPACT_HQ_HOUSING_BASELINE
					total_housing_capacity += housing_contrib
					residential_buildings.append({"building_id": bid, "capacity": housing_contrib})
				is_workplace = true
				wp_job_type = ""
				wp_quota = 0
				wp_buffer_cap = buf_override if buf_override >= 0 else DEFAULT_BUFFER_CAPACITY
				# A Market is a receiving buffer, NEVER a final Storehouse (Review F.1)
				wp_is_dropoff = false
				if wp_is_active and wp_buffer_cap > 0:
					caps.append(CAP_RECEIVING_BUFFER)
					caps.append(CAP_TRANSPORT_SOURCE)
					wp_output_res = EconomyConfigScript.RES_FOOD
					buffer_resources = [
						EconomyConfigScript.RES_FOOD,
						EconomyConfigScript.RES_WOOD,
						EconomyConfigScript.RES_STONE,
						EconomyConfigScript.RES_METAL,
						EconomyConfigScript.RES_TOOLS,
						EconomyConfigScript.RES_HERBS,
						EconomyConfigScript.RES_CRYSTAL
					]
					receiving_buffer_ids.append(bid)

			"farm":
				caps.append(CAP_WORKPLACE)
				caps.append(CAP_FOOD_PRODUCTION)
				is_workplace = true
				wp_job_type = SettlementVillagerDataScript.ROLE_FARMER
				wp_quota = q_override if q_override >= 0 else int(bp.get("max_workers", 5))
				wp_output_res = EconomyConfigScript.RES_FOOD
				wp_buffer_cap = buf_override if buf_override >= 0 else DEFAULT_BUFFER_CAPACITY
				wp_is_dropoff = false
				if wp_is_active and wp_buffer_cap > 0:
					caps.append(CAP_OUTPUT_BUFFER)
					caps.append(CAP_TRANSPORT_SOURCE)
					buffer_resources = [EconomyConfigScript.RES_FOOD]
					output_buffer_ids.append(bid)

			"woodcutter":
				caps.append(CAP_WORKPLACE)
				caps.append(CAP_WOOD_PRODUCTION)
				is_workplace = true
				wp_job_type = SettlementVillagerDataScript.ROLE_WOODCUTTER
				var is_compact_support_wc: bool = (house_count == 0 and String(b.get("role", "")) == "support")
				var default_wc_quota: int = PROVISIONAL_COMPACT_WOODCUTTER_QUOTA if is_compact_support_wc else int(bp.get("max_workers", 4))
				wp_quota = q_override if q_override >= 0 else default_wc_quota
				wp_output_res = EconomyConfigScript.RES_WOOD
				wp_buffer_cap = buf_override if buf_override >= 0 else DEFAULT_BUFFER_CAPACITY
				wp_is_dropoff = false
				if wp_is_active and wp_buffer_cap > 0:
					caps.append(CAP_OUTPUT_BUFFER)
					caps.append(CAP_TRANSPORT_SOURCE)
					buffer_resources = [EconomyConfigScript.RES_WOOD]
					output_buffer_ids.append(bid)

			"workshop":
				caps.append(CAP_WORKPLACE)
				caps.append(CAP_SMITH_RESTRICTED)
				is_workplace = true
				wp_job_type = SettlementVillagerDataScript.ROLE_SMITH
				wp_output_res = EconomyConfigScript.RES_METAL
				wp_buffer_cap = buf_override if buf_override >= 0 else WORKSHOP_BUFFER_CAPACITY
				wp_is_dropoff = false
				if smith_allowed and wp_is_active:
					wp_quota = q_override if q_override >= 0 else int(bp.get("max_workers", 4))
					wp_is_active = true
				else:
					wp_quota = 0
					wp_is_active = false

			"watchtower":
				caps.append(CAP_DEFENSE_STATIC)
				caps.append(CAP_PATROL_WAYPOINT)
				patrol_target_ids.append(bid)
				patrol_targets.append({
					"target_id": bid,
					"building_id": bid,
					"settlement_id": p_settlement_id,
					"building_type": "watchtower",
					"origin_cell": bcell,
					"size": bsize,
					"access_cell": access_c,
					"patrol_order_index": patrol_targets.size()
				})

			"palisade":
				caps.append(CAP_WALL_STATIC)

			_:
				caps.append(CAP_UNSUPPORTED)

		var desc: Dictionary = {
			"building_id": bid,
			"workplace_id": bid,
			"settlement_id": p_settlement_id,
			"building_type": btype,
			"level": blvl,
			"origin_cell": bcell,
			"size": bsize,
			"access_cell": access_c,
			"capabilities": caps,
			"housing_contribution": housing_contrib,
			"storage_contribution": storage_contrib,
			"is_workplace_record": is_workplace,
			"job_type": wp_job_type,
			"worker_quota": wp_quota if wp_is_active else 0,
			"hauler_worker_capacity": hauler_worker_cap,
			"output_resource": wp_output_res,
			"buffer_resources": buffer_resources,
			"buffer_capacity": wp_buffer_cap,
			"is_dropoff": wp_is_dropoff,
			"is_active": wp_is_active,
			"route_ids": []
		}
		building_descriptors.append(desc)
		descriptors_by_id[bid] = desc

		if enable_hunter and btype == "townhall":
			var hunter_wp_id := "%s__hunter" % bid
			var hunter_desc: Dictionary = {
				"building_id": bid,
				"workplace_id": hunter_wp_id,
				"settlement_id": p_settlement_id,
				"building_type": "townhall",
				"level": blvl,
				"origin_cell": bcell,
				"size": bsize,
				"access_cell": access_c,
				"capabilities": [CAP_WORKPLACE, "hunting_workplace"],
				"housing_contribution": 0,
				"storage_contribution": {},
				"is_workplace_record": true,
				"job_type": SettlementVillagerDataScript.ROLE_HUNTER,
				"worker_quota": 1,
				"hauler_worker_capacity": 0,
				"output_resource": EconomyConfigScript.RES_RAW_MEAT,
				"buffer_resources": [EconomyConfigScript.RES_RAW_MEAT],
				"buffer_capacity": DEFAULT_BUFFER_CAPACITY,
				"is_dropoff": true,
				"is_active": wp_is_active,
				"route_ids": []
			}
			building_descriptors.append(hunter_desc)
			descriptors_by_id[hunter_wp_id] = hunter_desc

	# Second pass: validate transport routes from distinct receiving buffers & production output buffers
	# to final storage destinations (Storehouse when present, or Townhall/Barracks final storage fallback).
	var transport_routes: Array[Dictionary] = []
	var candidate_source_ids: Array[String] = []
	for r_id in receiving_buffer_ids:
		if not candidate_source_ids.has(r_id):
			candidate_source_ids.append(r_id)
	for o_id in output_buffer_ids:
		if not candidate_source_ids.has(o_id):
			candidate_source_ids.append(o_id)

	var candidate_dest_ids: Array[String] = storehouse_ids if not storehouse_ids.is_empty() else final_storage_ids

	for src_id in candidate_source_ids:
		var src_desc: Dictionary = descriptors_by_id[src_id]
		var primary_res: String = String(src_desc.get("output_resource", EconomyConfigScript.RES_FOOD))
		if primary_res.is_empty():
			primary_res = EconomyConfigScript.RES_FOOD
		for dst_id in candidate_dest_ids:
			var dst_desc: Dictionary = descriptors_by_id[dst_id]
			var route_check := validate_transport_route(p_settlement_id, src_desc, dst_desc, primary_res)
			if bool(route_check.get("ok", false)):
				transport_routes.append(route_check)
				if bool(dst_desc["is_active"]):
					dst_desc["worker_quota"] = int(dst_desc["hauler_worker_capacity"])
				dst_desc["job_type"] = SettlementVillagerDataScript.ROLE_HAULER
				if not (dst_desc["capabilities"] as Array).has(CAP_WORKPLACE):
					(dst_desc["capabilities"] as Array).append(CAP_WORKPLACE)
				if not dst_desc.has("source_building_id"):
					dst_desc["source_building_id"] = src_id
					dst_desc["source_cell"] = src_desc["access_cell"]
					dst_desc["cargo_resource"] = primary_res
				(dst_desc["route_ids"] as Array).append(String(route_check["route_id"]))

	# Second-and-a-half pass: build deterministic Guard Patrol descriptors for Barracks workplaces
	# linking each Barracks to all valid Watchtower patrol waypoints in the same settlement (Review B).
	var guard_patrol_descriptors: Array[Dictionary] = []
	for desc in building_descriptors:
		if String(desc["building_type"]) == "barracks" and bool(desc["is_workplace_record"]):
			var b_id: String = String(desc["building_id"])
			var b_access: Vector2i = desc["access_cell"]
			var waypoints: Array[Dictionary] = [{
				"waypoint_id": b_id,
				"building_id": b_id,
				"building_type": "barracks",
				"settlement_id": p_settlement_id,
				"access_cell": b_access,
				"order_index": 0
			}]
			for pt in patrol_targets:
				waypoints.append({
					"waypoint_id": String(pt["building_id"]),
					"building_id": String(pt["building_id"]),
					"building_type": "watchtower",
					"settlement_id": p_settlement_id,
					"access_cell": pt["access_cell"],
					"order_index": waypoints.size()
				})
			var gp_desc: Dictionary = {
				"patrol_id": "patrol__%s__%s" % [p_settlement_id, b_id],
				"settlement_id": p_settlement_id,
				"barracks_building_id": b_id,
				"barracks_workplace_id": String(desc["workplace_id"]),
				"barracks_access_cell": b_access,
				"watchtower_ids": patrol_target_ids.duplicate(),
				"patrol_targets": patrol_targets.duplicate(true),
				"waypoints": waypoints
			}
			guard_patrol_descriptors.append(gp_desc)
			desc["patrol_id"] = gp_desc["patrol_id"]
			desc["patrol_target_ids"] = patrol_target_ids.duplicate()
			desc["patrol_targets"] = patrol_targets.duplicate(true)

	# Third pass: build deterministic job descriptors for all active workplaces with worker_quota > 0
	var job_descriptors: Array[Dictionary] = []
	for desc in building_descriptors:
		if not bool(desc["is_workplace_record"]) or not bool(desc["is_active"]):
			continue
		var quota: int = int(desc["worker_quota"])
		var jtype: String = String(desc["job_type"])
		if quota <= 0 or jtype.is_empty():
			continue
		var wpid: String = String(desc["workplace_id"])
		var prio: int = _get_priority_for_role(jtype)
		var req_hours: float = float(DEFAULT_WORK_HOURS_BY_ROLE.get(jtype, 2.0))
		var base_t_cell: Vector2i = desc["access_cell"]
		var base_s_cell: Vector2i = desc.get("source_cell", base_t_cell)
		var base_d_cell: Vector2i = base_t_cell
		var c_res: String = String(desc.get("cargo_resource", desc.get("output_resource", "")))

		for slot_idx in range(1, quota + 1):
			var jid := format_deterministic_job_id(p_settlement_id, wpid, jtype, slot_idx)
			var slot_t_cell: Vector2i = base_t_cell
			var slot_s_cell: Vector2i = base_s_cell
			var slot_d_cell: Vector2i = base_d_cell
			var patrol_tid: String = ""
			if jtype == SettlementVillagerDataScript.ROLE_GUARD:
				slot_s_cell = base_t_cell
				if not patrol_targets.is_empty():
					var pt_cur: Dictionary = patrol_targets[(slot_idx - 1) % patrol_targets.size()]
					var pt_nxt: Dictionary = patrol_targets[slot_idx % patrol_targets.size()]
					slot_t_cell = pt_cur["access_cell"]
					slot_d_cell = pt_nxt["access_cell"]
					patrol_tid = String(pt_cur["building_id"])
				else:
					slot_t_cell = base_t_cell
					slot_d_cell = base_t_cell
					patrol_tid = wpid
			job_descriptors.append({
				"job_id": jid,
				"settlement_id": p_settlement_id,
				"job_type": jtype,
				"workplace_id": wpid,
				"slot_index": slot_idx,
				"target_cell": slot_t_cell,
				"source_cell": slot_s_cell,
				"dest_cell": slot_d_cell,
				"work_hours_required": req_hours,
				"priority": prio,
				"cargo_resource": c_res,
				"patrol_target_id": patrol_tid
			})

	return {
		"ok": true,
		"settlement_id": p_settlement_id,
		"origin_faction_id": p_origin_faction_id,
		"housing_capacity": total_housing_capacity,
		"residential_buildings": residential_buildings,
		"derived_capacities": derived_capacities,
		"derived_capacity_bonuses": derived_capacity_bonuses,
		"building_descriptors": building_descriptors,
		"final_storage_ids": final_storage_ids,
		"receiving_buffer_ids": receiving_buffer_ids,
		"output_buffer_ids": output_buffer_ids,
		"transport_routes": transport_routes,
		"patrol_target_ids": patrol_target_ids,
		"patrol_targets": patrol_targets,
		"guard_patrol_descriptors": guard_patrol_descriptors,
		"job_descriptors": job_descriptors,
		"ignored_duplicate_ids": ignored_duplicate_ids
	}

static func _get_priority_for_role(role: String) -> int:
	match role:
		SettlementVillagerDataScript.ROLE_GUARD:
			return PRIORITY_GUARD
		SettlementVillagerDataScript.ROLE_HUNTER:
			return PRIORITY_HUNTER
		SettlementVillagerDataScript.ROLE_FARMER:
			return PRIORITY_FARMER
		SettlementVillagerDataScript.ROLE_WOODCUTTER:
			return PRIORITY_WOODCUTTER
		SettlementVillagerDataScript.ROLE_HAULER:
			return PRIORITY_HAULER
		SettlementVillagerDataScript.ROLE_SMITH:
			return PRIORITY_SMITH
		_:
			return 1

static func _get_default_job_type_for_building_type(btype: String, is_dropoff: bool) -> String:
	match btype:
		"barracks":
			return SettlementVillagerDataScript.ROLE_GUARD
		"farm":
			return SettlementVillagerDataScript.ROLE_FARMER
		"woodcutter":
			return SettlementVillagerDataScript.ROLE_WOODCUTTER
		"storehouse":
			return SettlementVillagerDataScript.ROLE_HAULER
		"townhall":
			return SettlementVillagerDataScript.ROLE_HAULER if is_dropoff else ""
		"workshop":
			return SettlementVillagerDataScript.ROLE_SMITH
		_:
			return ""

## Atomically reconciles a `SettlementVillagerContext` against canonical `buildings` (`SettlementData.buildings`).
## Safe to call repeatedly (idempotent): preserves existing workplace buffers (never clamping downward when
## capacity decreases), active job progress, and valid villager assignments while removing stale workplaces/jobs
## and assigning open slots deterministically.
static func reconcile_context_with_buildings(
	ctx: RefCounted,
	buildings: Variant,
	strict_reject_malformed: bool = true,
	enable_hunter: bool = false
) -> Dictionary:
	if ctx == null or not ctx.has_method("is_valid") or not ctx.is_valid():
		return {"ok": false, "reason": "invalid_context"}

	var eff_hunter: bool = enable_hunter or (ctx != null and ctx.has_meta("enable_hunter") and bool(ctx.get_meta("enable_hunter")))
	var derived := derive_capabilities_from_buildings(
		ctx.settlement_id,
		ctx.origin_faction_id,
		buildings,
		ctx.economy,
		strict_reject_malformed,
		eff_hunter
	)
	if not bool(derived.get("ok", false)):
		return derived

	# 1. Reconcile SettlementEconomy storage capacities (explicitly replaces prior bonuses; never destroys stock)
	if ctx.economy != null and ctx.economy.has_method("apply_derived_capacities"):
		var cap_res: Dictionary = ctx.economy.apply_derived_capacities(
			derived["derived_capacities"],
			derived["derived_capacity_bonuses"]
		)
		if not bool(cap_res.get("ok", false)):
			return cap_res

	# 2. Reconcile SettlementWorkplaceRegistry (update/add current workplaces, remove obsolete ones without losing buffers)
	var desired_wp_by_id: Dictionary = {}
	for desc in derived["building_descriptors"]:
		if bool(desc["is_workplace_record"]):
			desired_wp_by_id[String(desc["workplace_id"])] = desc

	var existing_wps: Array = ctx.workplace_registry.get_all_workplaces()
	for old_wp in existing_wps:
		if not desired_wp_by_id.has(old_wp.workplace_id):
			if int(old_wp.buffer_amount) > 0:
				var prev_salv: int = 0
				if ctx._salvaged_workplace_buffers.has(old_wp.workplace_id):
					prev_salv = int(ctx._salvaged_workplace_buffers[old_wp.workplace_id].get("amount", 0))
				ctx._salvaged_workplace_buffers[old_wp.workplace_id] = {
					"workplace_id": old_wp.workplace_id,
					"building_id": old_wp.building_id,
					"building_type": old_wp.building_type,
					"resource": old_wp.output_resource,
					"amount": prev_salv + int(old_wp.buffer_amount)
				}
			ctx._workplace_effective_buffer_capacities.erase(old_wp.workplace_id)
			ctx.workplace_registry.unregister_workplace(old_wp.workplace_id)

	for wpid in desired_wp_by_id.keys():
		var desc: Dictionary = desired_wp_by_id[wpid]
		var new_eff_cap: int = maxi(0, int(desc["buffer_capacity"]))
		ctx._workplace_effective_buffer_capacities[wpid] = new_eff_cap
		if ctx.workplace_registry.has_workplace(wpid):
			var live_wp = ctx.workplace_registry.get_workplace(wpid)
			var preserved_buf_amt: int = maxi(0, int(live_wp.buffer_amount))
			live_wp.building_type = String(desc["building_type"])
			live_wp.origin_cell = desc["origin_cell"]
			live_wp.size = desc["size"]
			live_wp.access_cell = desc["access_cell"]
			live_wp.output_resource = String(desc["output_resource"])
			# Review B: Never clamp buffer_amount downward when derived capacity decreases!
			live_wp.buffer_amount = preserved_buf_amt
			live_wp.buffer_capacity = maxi(new_eff_cap, preserved_buf_amt)
			live_wp.worker_quota = int(desc["worker_quota"])
			live_wp.is_dropoff = bool(desc["is_dropoff"])
			live_wp.is_active = bool(desc["is_active"])
		else:
			var restored_buf_amt: int = 0
			if ctx._salvaged_workplace_buffers.has(wpid):
				var salv_entry: Dictionary = ctx._salvaged_workplace_buffers[wpid]
				if String(salv_entry.get("resource", "")) == String(desc["output_resource"]):
					restored_buf_amt = maxi(0, int(salv_entry.get("amount", 0)))
					ctx._salvaged_workplace_buffers.erase(wpid)
			var initial_ceil_cap: int = maxi(new_eff_cap, restored_buf_amt)
			var created_wp = ctx.workplace_registry.register_workplace(
				wpid,
				String(desc["building_type"]),
				desc["origin_cell"],
				desc["size"],
				desc["access_cell"],
				String(desc["output_resource"]),
				initial_ceil_cap,
				int(desc["worker_quota"]),
				bool(desc["is_dropoff"]),
				String(desc["building_id"])
			)
			if created_wp != null:
				created_wp.buffer_amount = restored_buf_amt
				created_wp.is_active = bool(desc["is_active"])

	# 3. Reconcile SettlementJobBoard (preserve existing matching job records, remove obsolete ones, register new ones)
	var desired_jobs_by_id: Dictionary = {}
	for jdesc in derived["job_descriptors"]:
		desired_jobs_by_id[String(jdesc["job_id"])] = jdesc

	var existing_jobs: Array = ctx.job_board.get_all_jobs()
	for old_job in existing_jobs:
		if not desired_jobs_by_id.has(old_job.job_id):
			ctx.job_board.remove_job(old_job.job_id)

	for jid in desired_jobs_by_id.keys():
		var jdesc: Dictionary = desired_jobs_by_id[jid]
		if ctx.job_board.has_job(jid):
			var live_job = ctx.job_board.get_job(jid)
			live_job.job_type = String(jdesc["job_type"])
			live_job.workplace_id = String(jdesc["workplace_id"])
			live_job.target_cell = jdesc["target_cell"]
			live_job.source_cell = jdesc["source_cell"]
			live_job.dest_cell = jdesc["dest_cell"]
			live_job.work_hours_required = float(jdesc["work_hours_required"])
			live_job.priority = int(jdesc["priority"])
			live_job.cargo_resource = String(jdesc["cargo_resource"])
			if live_job.state == SettlementJobBoardScript.STATE_CANCELLED or live_job.state == SettlementJobBoardScript.STATE_COMPLETED:
				live_job.state = SettlementJobBoardScript.STATE_AVAILABLE
		else:
			var rec := SettlementJobBoardScript.NpcJobRecord.new()
			rec.job_id = jid
			rec.settlement_id = ctx.settlement_id
			rec.job_type = String(jdesc["job_type"])
			rec.workplace_id = String(jdesc["workplace_id"])
			rec.target_cell = jdesc["target_cell"]
			rec.source_cell = jdesc["source_cell"]
			rec.dest_cell = jdesc["dest_cell"]
			rec.state = SettlementJobBoardScript.STATE_AVAILABLE
			rec.assigned_villager_id = ""
			rec.work_hours_required = float(jdesc["work_hours_required"])
			rec.work_hours_done = 0.0
			rec.priority = int(jdesc["priority"])
			rec.cargo_resource = String(jdesc["cargo_resource"])
			rec.cargo_amount = 0
			ctx.job_board.register_job(rec)

	# 4. Update context housing & derived capability metadata
	ctx._set_derived_building_state(
		int(derived["housing_capacity"]),
		derived["residential_buildings"],
		derived["building_descriptors"],
		derived["final_storage_ids"],
		derived["receiving_buffer_ids"],
		derived["transport_routes"],
		derived["output_buffer_ids"],
		derived["patrol_target_ids"],
		derived["patrol_targets"],
		derived["guard_patrol_descriptors"]
	)

	# 5. Reconcile residential home_building_id and deterministic job assignments
	_reconcile_residential_assignments(ctx, derived["residential_buildings"])
	var assign_res := assign_villagers_deterministically(ctx)

	return {
		"ok": true,
		"settlement_id": ctx.settlement_id,
		"housing_capacity": int(derived["housing_capacity"]),
		"workplace_count": ctx.workplace_registry.get_workplace_count(),
		"job_count": ctx.job_board.get_job_count(),
		"transport_route_count": (derived["transport_routes"] as Array).size(),
		"assigned_villager_count": int(assign_res.get("assigned_count", 0)),
		"idle_villager_count": int(assign_res.get("idle_count", 0)),
		"derived": derived
	}

static func _reconcile_residential_assignments(ctx: RefCounted, residential_buildings: Array) -> void:
	var cap_by_bld: Dictionary = {}
	var used_by_bld: Dictionary = {}
	var ordered_bld_ids: Array[String] = []
	for rb in residential_buildings:
		var bid: String = String(rb["building_id"])
		var bcap: int = int(rb["capacity"])
		if bcap > 0:
			cap_by_bld[bid] = bcap
			used_by_bld[bid] = 0
			ordered_bld_ids.append(bid)

	var villagers: Array = ctx.get_all_villagers()
	# Preserve valid existing home_building_id assignments first
	for v in villagers:
		if v.life_state != SettlementVillagerDataScript.LIFE_ALIVE:
			v.home_building_id = ""
			continue
		var cur_home: String = v.home_building_id
		if not cur_home.is_empty() and cap_by_bld.has(cur_home) and int(used_by_bld[cur_home]) < int(cap_by_bld[cur_home]):
			used_by_bld[cur_home] = int(used_by_bld[cur_home]) + 1
		else:
			v.home_building_id = ""

	# Assign remaining unhoused alive villagers to available residential slots in deterministic order
	for v in villagers:
		if v.life_state != SettlementVillagerDataScript.LIFE_ALIVE or not v.home_building_id.is_empty():
			continue
		for bid in ordered_bld_ids:
			if int(used_by_bld[bid]) < int(cap_by_bld[bid]):
				v.home_building_id = bid
				used_by_bld[bid] = int(used_by_bld[bid]) + 1
				break

## Synchronizes deterministic job slots on `ctx.job_board` when a workplace's `worker_quota` or `is_active`
## state has been modified directly on `NpcWorkplaceRecord`.
static func _sync_job_board_with_workplace_quotas(ctx: RefCounted) -> void:
	if ctx == null or ctx.workplace_registry == null or ctx.job_board == null:
		return
	var all_wps: Array = ctx.workplace_registry.get_all_workplaces()
	var wp_map: Dictionary = {}
	for wp in all_wps:
		wp_map[wp.workplace_id] = wp

	# Remove or cancel deterministic job slots that exceed current wp.worker_quota or belong to inactive/removed workplaces
	for j in ctx.job_board.get_all_jobs():
		var parsed: Dictionary = parse_deterministic_job_id(j.job_id)
		if parsed.is_empty():
			continue
		var wpid: String = String(parsed["workplace_id"])
		var slot_idx: int = int(parsed["slot_index"])
		if not wp_map.has(wpid):
			ctx.job_board.remove_job(j.job_id)
			continue
		var wp = wp_map[wpid]
		if not wp.is_active or wp.worker_quota <= 0 or slot_idx > wp.worker_quota:
			ctx.job_board.remove_job(j.job_id)
		elif j.state == SettlementJobBoardScript.STATE_CANCELLED:
			j.state = SettlementJobBoardScript.STATE_AVAILABLE

	# Ensure deterministic job slots 1..wp.worker_quota exist for active workplaces
	for wp in all_wps:
		if not wp.is_active or wp.worker_quota <= 0:
			continue
		var jtype: String = ""
		if wp.output_resource == EconomyConfigScript.RES_RAW_MEAT or wp.workplace_id.ends_with("__hunter"):
			jtype = SettlementVillagerDataScript.ROLE_HUNTER
		else:
			jtype = _get_default_job_type_for_building_type(wp.building_type, wp.is_dropoff)
		if jtype.is_empty():
			continue
		if jtype == SettlementVillagerDataScript.ROLE_SMITH:
			if ctx.economy == null or not bool(ctx.economy.get("merchant_smith_enabled")) or int(ctx.economy.get_resource(EconomyConfigScript.RES_ORE)) < 2:
				wp.worker_quota = 0
				wp.is_active = false
				continue
		var prio: int = _get_priority_for_role(jtype)
		var req_hours: float = float(DEFAULT_WORK_HOURS_BY_ROLE.get(jtype, 2.0))
		for slot_idx in range(1, wp.worker_quota + 1):
			var jid := format_deterministic_job_id(ctx.settlement_id, wp.workplace_id, jtype, slot_idx)
			if ctx.job_board.has_job(jid):
				var existing_j = ctx.job_board.get_job(jid)
				if existing_j.state == SettlementJobBoardScript.STATE_CANCELLED:
					existing_j.state = SettlementJobBoardScript.STATE_AVAILABLE
			else:
				var rec := SettlementJobBoardScript.NpcJobRecord.new()
				rec.job_id = jid
				rec.settlement_id = ctx.settlement_id
				rec.job_type = jtype
				rec.workplace_id = wp.workplace_id
				rec.target_cell = wp.access_cell
				rec.source_cell = wp.access_cell
				rec.dest_cell = wp.access_cell
				rec.state = SettlementJobBoardScript.STATE_AVAILABLE
				rec.assigned_villager_id = ""
				rec.work_hours_required = req_hours
				rec.work_hours_done = 0.0
				rec.priority = prio
				rec.cargo_resource = wp.output_resource
				rec.cargo_amount = 0
				ctx.job_board.register_job(rec)

## Explicitly registers a Town Hall Hunter workplace (1 quota) and posts its deterministic job.
## Idempotent: safe to call repeatedly without duplicating workplaces or jobs.
static func register_hunter_workplace(ctx: RefCounted, townhall_id: String = "") -> Dictionary:
	if ctx == null or not ctx.has_method("is_valid") or not ctx.is_valid():
		return {"ok": false, "reason": "invalid_context"}

	var target_th_id := townhall_id.strip_edges()
	var th_wp = null
	if target_th_id.is_empty():
		for wp in ctx.workplace_registry.get_all_workplaces():
			if wp.building_type == "townhall":
				th_wp = wp
				target_th_id = wp.building_id
				break
	else:
		th_wp = ctx.workplace_registry.get_workplace(target_th_id)
		if th_wp == null:
			for wp in ctx.workplace_registry.get_all_workplaces():
				if wp.building_id == target_th_id:
					th_wp = wp
					break

	if target_th_id.is_empty() or th_wp == null:
		return {"ok": false, "reason": "townhall_not_found"}

	var hunter_wpid := "%s__hunter" % target_th_id
	var access_c: Vector2i = th_wp.access_cell
	var hunter_desc: Dictionary = {
		"building_id": target_th_id,
		"workplace_id": hunter_wpid,
		"settlement_id": ctx.settlement_id,
		"building_type": "townhall",
		"level": th_wp.level if "level" in th_wp else 1,
		"origin_cell": th_wp.origin_cell,
		"size": th_wp.size,
		"access_cell": access_c,
		"capabilities": [CAP_WORKPLACE, "hunting_workplace"],
		"housing_contribution": 0,
		"storage_contribution": {},
		"is_workplace_record": true,
		"job_type": SettlementVillagerDataScript.ROLE_HUNTER,
		"worker_quota": 1,
		"hauler_worker_capacity": 0,
		"output_resource": EconomyConfigScript.RES_RAW_MEAT,
		"buffer_resources": [EconomyConfigScript.RES_RAW_MEAT],
		"buffer_capacity": DEFAULT_BUFFER_CAPACITY,
		"is_dropoff": true,
		"is_active": true,
		"route_ids": []
	}

	if not ctx.workplace_registry.has_workplace(hunter_wpid):
		ctx.workplace_registry.register_workplace(hunter_desc)

	var jid := format_deterministic_job_id(ctx.settlement_id, hunter_wpid, SettlementVillagerDataScript.ROLE_HUNTER, 1)
	if not ctx.job_board.has_job(jid):
		var rec := SettlementJobBoardScript.NpcJobRecord.new()
		rec.job_id = jid
		rec.settlement_id = ctx.settlement_id
		rec.job_type = SettlementVillagerDataScript.ROLE_HUNTER
		rec.workplace_id = hunter_wpid
		rec.target_cell = access_c
		rec.source_cell = access_c
		rec.dest_cell = access_c
		rec.state = SettlementJobBoardScript.STATE_AVAILABLE
		rec.assigned_villager_id = ""
		rec.work_hours_required = 2.5
		rec.work_hours_done = 0.0
		rec.priority = PRIORITY_HUNTER
		rec.cargo_resource = EconomyConfigScript.RES_RAW_MEAT
		rec.cargo_amount = 0
		ctx.job_board.register_job(rec)

	ctx.set_meta("enable_hunter", true)
	return {"ok": true, "workplace_id": hunter_wpid, "job_id": jid}

static func _resolve_guard_patrol_target_for_job(ctx: RefCounted, job: RefCounted, current_target_id: String = "") -> String:
	if ctx == null or job == null or job.job_type != SettlementVillagerDataScript.ROLE_GUARD:
		return ""
	var patrol_ids: Array = ctx.get_patrol_target_ids() if ctx.has_method("get_patrol_target_ids") else []
	if patrol_ids.is_empty():
		return job.workplace_id
	var clean_cur := current_target_id.strip_edges()
	if not clean_cur.is_empty() and patrol_ids.has(clean_cur):
		return clean_cur
	var parsed: Dictionary = parse_deterministic_job_id(job.job_id)
	var slot_idx: int = maxi(1, int(parsed.get("slot_index", 1)))
	return String(patrol_ids[(slot_idx - 1) % patrol_ids.size()])

## Deterministic initial job assignment and reconciliation for a `SettlementVillagerContext`.
## Ordering policy:
##   1. Sync deterministic job slots with current workplace quotas and active flags.
##   2. Preserve existing valid (villager <-> active job) pairs where workplace is active and within quota.
##   3. Conditional Hauler reservation (Review A): if a valid transport route's source workplace has
##      `buffer_amount > 0` (goods waiting for transfer) and its destination Hauler workplace currently has
##      0 workers, reserve 1 Hauler slot ahead of secondary (`slot_index >= 2`) production slots.
##   4. Clear any invalid, orphaned, over-quota, or duplicate assignments on both villagers and jobs.
##   5. Sort remaining open job slots by descending effective `priority`, then ascending `job_id`.
##   6. Sort unassigned alive villagers by ascending sequence number / `villager_id`.
##   7. Pair each open job slot 1:1 with the next unassigned villager; excess villagers remain `idle`.
static func assign_villagers_deterministically(ctx: RefCounted) -> Dictionary:
	if ctx == null or not ctx.has_method("is_valid") or not ctx.is_valid():
		return {"ok": false, "reason": "invalid_context"}

	_sync_job_board_with_workplace_quotas(ctx)

	var villagers: Array = ctx.get_all_villagers()
	var all_jobs: Array = ctx.job_board.get_all_jobs()

	var valid_open_or_active_jobs_by_id: Dictionary = {}
	var max_quota_by_wp: Dictionary = {}
	var used_quota_by_wp: Dictionary = {}

	for j in all_jobs:
		if j.settlement_id != ctx.settlement_id:
			continue
		if j.state == SettlementJobBoardScript.STATE_CANCELLED or j.state == SettlementJobBoardScript.STATE_COMPLETED:
			continue
		var wp = ctx.workplace_registry.get_workplace(j.workplace_id)
		if wp == null or wp.settlement_id != ctx.settlement_id or not wp.is_active or wp.worker_quota <= 0:
			continue
		max_quota_by_wp[wp.workplace_id] = int(wp.worker_quota)
		if not used_quota_by_wp.has(wp.workplace_id):
			used_quota_by_wp[wp.workplace_id] = 0
		valid_open_or_active_jobs_by_id[j.job_id] = j

	# Identify Hauler workplaces whose validated source buffers currently have pending goods (buffer_amount > 0)
	var hauler_wps_with_pending_source_buffer: Dictionary = {} # dest_wp_id -> Array[src_wp_id]
	var routes: Array = ctx.get_transport_routes() if ctx.has_method("get_transport_routes") else []
	for r in routes:
		if not (r is Dictionary):
			continue
		var src_wp_id: String = String(r.get("source_workplace_id", r.get("source_building_id", "")))
		var dst_wp_id: String = String(r.get("dest_workplace_id", r.get("dest_building_id", "")))
		var src_wp = ctx.workplace_registry.get_workplace(src_wp_id)
		var dst_wp = ctx.workplace_registry.get_workplace(dst_wp_id)
		if src_wp != null and dst_wp != null and dst_wp.is_active and dst_wp.worker_quota > 0 and int(src_wp.buffer_amount) > 0:
			if not hauler_wps_with_pending_source_buffer.has(dst_wp_id):
				hauler_wps_with_pending_source_buffer[dst_wp_id] = []
			(hauler_wps_with_pending_source_buffer[dst_wp_id] as Array).append(src_wp_id)

	var claimed_job_ids: Dictionary = {}
	var preserved_villager_ids: Dictionary = {}

	# Step 1: Validate and preserve existing valid assignments in deterministic villager order
	for v in villagers:
		if v.settlement_id != ctx.settlement_id or v.life_state != SettlementVillagerDataScript.LIFE_ALIVE:
			v.active_job_id = ""
			v.workplace_id = ""
			v.work_target_id = ""
			v.role = SettlementVillagerDataScript.ROLE_IDLE
			v.task_state = SettlementVillagerDataScript.TASK_IDLE
			continue

		var cur_jid: String = v.active_job_id
		if not cur_jid.is_empty() and valid_open_or_active_jobs_by_id.has(cur_jid) and not claimed_job_ids.has(cur_jid):
			var j = valid_open_or_active_jobs_by_id[cur_jid]
			var wpid: String = j.workplace_id
			var wp_used: int = int(used_quota_by_wp.get(wpid, 0))
			var wp_max: int = int(max_quota_by_wp.get(wpid, 0))
			var wp_match: bool = v.workplace_id.is_empty() or v.workplace_id == wpid
			var job_villager_match: bool = j.assigned_villager_id.is_empty() or j.assigned_villager_id == v.villager_id
			if wp_used < wp_max and wp_match and job_villager_match:
				claimed_job_ids[cur_jid] = v.villager_id
				preserved_villager_ids[v.villager_id] = cur_jid
				used_quota_by_wp[wpid] = wp_used + 1
				j.assigned_villager_id = v.villager_id
				if j.state == SettlementJobBoardScript.STATE_AVAILABLE:
					j.state = SettlementJobBoardScript.STATE_RESERVED
				v.workplace_id = wpid
				v.role = j.job_type
				if j.job_type == SettlementVillagerDataScript.ROLE_GUARD:
					v.work_target_id = _resolve_guard_patrol_target_for_job(ctx, j, v.work_target_id)
				continue

		# Stale, over-quota, or invalid assignment on villager: clear to idle
		v.active_job_id = ""
		v.workplace_id = ""
		v.work_target_id = ""
		v.role = SettlementVillagerDataScript.ROLE_IDLE
		v.task_state = SettlementVillagerDataScript.TASK_IDLE

	# Step 1b: Conditional Hauler release when a source buffer has pending goods (buffer_amount > 0),
	# its destination Hauler workplace has 0 assigned workers, no unassigned alive villagers remain,
	# and a feeding source workplace currently holds >= 2 workers.
	var unassigned_alive_count: int = 0
	for v in villagers:
		if v.settlement_id == ctx.settlement_id and v.life_state == SettlementVillagerDataScript.LIFE_ALIVE and not preserved_villager_ids.has(v.villager_id):
			unassigned_alive_count += 1

	if unassigned_alive_count == 0 and not hauler_wps_with_pending_source_buffer.is_empty():
		for dst_wp_id in hauler_wps_with_pending_source_buffer.keys():
			if int(used_quota_by_wp.get(dst_wp_id, 0)) > 0:
				continue
			var src_ids: Array = hauler_wps_with_pending_source_buffer[dst_wp_id]
			for src_wp_id in src_ids:
				if int(used_quota_by_wp.get(src_wp_id, 0)) >= 2:
					# Release the last preserved villager on src_wp_id so they can staff dst_wp_id's conditional Hauler slot
					for idx in range(villagers.size() - 1, -1, -1):
						var cand_v = villagers[idx]
						if preserved_villager_ids.has(cand_v.villager_id) and cand_v.workplace_id == src_wp_id:
							var rel_jid: String = cand_v.active_job_id
							preserved_villager_ids.erase(cand_v.villager_id)
							claimed_job_ids.erase(rel_jid)
							used_quota_by_wp[src_wp_id] = maxi(0, int(used_quota_by_wp[src_wp_id]) - 1)
							cand_v.active_job_id = ""
							cand_v.workplace_id = ""
							cand_v.work_target_id = ""
							cand_v.role = SettlementVillagerDataScript.ROLE_IDLE
							cand_v.task_state = SettlementVillagerDataScript.TASK_IDLE
							break
					break

	# Step 2: Reset any job on the board that is not claimed by a preserved villager
	var candidate_open_jobs: Array = []
	for j in all_jobs:
		if not valid_open_or_active_jobs_by_id.has(j.job_id):
			j.assigned_villager_id = ""
			if j.state != SettlementJobBoardScript.STATE_COMPLETED:
				j.state = SettlementJobBoardScript.STATE_CANCELLED
			continue
		if not claimed_job_ids.has(j.job_id):
			j.assigned_villager_id = ""
			j.state = SettlementJobBoardScript.STATE_AVAILABLE
			candidate_open_jobs.append(j)

	# Step 3: Sort candidate open jobs by descending effective priority, then ascending job_id.
	# If a Hauler slot 1 belongs to a workplace with pending source buffer goods and 0 currently assigned Haulers,
	# its effective priority is boosted to (PRIORITY_FARMER) so it ranks after slot 1 of production (`slot_index == 1`
	# of Farmer/Woodcutter gets +1 slot-1 tie-break bonus) and ahead of secondary (`slot_index >= 2`) Woodcutter slots.
	candidate_open_jobs.sort_custom(func(a, b) -> bool:
		var pa: Dictionary = parse_deterministic_job_id(a.job_id)
		var pb: Dictionary = parse_deterministic_job_id(b.job_id)
		var slot_a: int = int(pa.get("slot_index", 1))
		var slot_b: int = int(pb.get("slot_index", 1))
		var eff_a: int = a.priority * 10 + (1 if slot_a == 1 else 0)
		var eff_b: int = b.priority * 10 + (1 if slot_b == 1 else 0)
		if a.job_type == SettlementVillagerDataScript.ROLE_HAULER and slot_a == 1 and hauler_wps_with_pending_source_buffer.has(a.workplace_id) and int(used_quota_by_wp.get(a.workplace_id, 0)) == 0:
			eff_a = PRIORITY_WOODCUTTER * 10 # Ranks right after Woodcutter slot 1 (71) and above Woodcutter slot 2 (70)
		if b.job_type == SettlementVillagerDataScript.ROLE_HAULER and slot_b == 1 and hauler_wps_with_pending_source_buffer.has(b.workplace_id) and int(used_quota_by_wp.get(b.workplace_id, 0)) == 0:
			eff_b = PRIORITY_WOODCUTTER * 10
		if eff_a != eff_b:
			return eff_a > eff_b
		return a.job_id < b.job_id
	)

	var open_jobs: Array = []
	var staged_quota_by_wp: Dictionary = used_quota_by_wp.duplicate()
	for j in candidate_open_jobs:
		var wpid: String = j.workplace_id
		var cur_q: int = int(staged_quota_by_wp.get(wpid, 0))
		var max_q: int = int(max_quota_by_wp.get(wpid, 0))
		if cur_q < max_q:
			staged_quota_by_wp[wpid] = cur_q + 1
			open_jobs.append(j)
		else:
			j.assigned_villager_id = ""
			j.state = SettlementJobBoardScript.STATE_CANCELLED

	# Step 4 & 5: Assign unassigned alive villagers in deterministic sequence order
	var open_idx: int = 0
	for v in villagers:
		if v.settlement_id != ctx.settlement_id or v.life_state != SettlementVillagerDataScript.LIFE_ALIVE:
			continue
		if preserved_villager_ids.has(v.villager_id):
			continue
		if open_idx < open_jobs.size():
			var job = open_jobs[open_idx]
			open_idx += 1
			job.assigned_villager_id = v.villager_id
			job.state = SettlementJobBoardScript.STATE_RESERVED
			v.active_job_id = job.job_id
			v.workplace_id = job.workplace_id
			v.role = job.job_type
			if job.job_type == SettlementVillagerDataScript.ROLE_GUARD:
				v.work_target_id = _resolve_guard_patrol_target_for_job(ctx, job, v.work_target_id)
			else:
				v.work_target_id = ""
		else:
			v.active_job_id = ""
			v.workplace_id = ""
			v.work_target_id = ""
			v.role = SettlementVillagerDataScript.ROLE_IDLE
			v.task_state = SettlementVillagerDataScript.TASK_IDLE

	var assigned_count: int = 0
	var idle_count: int = 0
	for v in villagers:
		if v.life_state == SettlementVillagerDataScript.LIFE_ALIVE:
			if v.active_job_id.is_empty():
				idle_count += 1
			else:
				assigned_count += 1

	return {
		"ok": true,
		"assigned_count": assigned_count,
		"idle_count": idle_count,
		"open_job_slots_remaining": maxi(0, open_jobs.size() - open_idx)
	}

## Verifies strict 4-way consistency between Villager <-> Job <-> Workplace <-> Canonical Building ID.
static func verify_context_assignment_integrity(ctx: RefCounted) -> Dictionary:
	if ctx == null or not ctx.has_method("is_valid") or not ctx.is_valid():
		return {"ok": false, "reason": "invalid_context"}

	var villagers: Array = ctx.get_all_villagers()
	var jobs: Array = ctx.job_board.get_all_jobs()
	var seen_job_to_villager: Dictionary = {}
	var seen_villager_to_job: Dictionary = {}
	var workers_per_wp: Dictionary = {}

	for v in villagers:
		if v.settlement_id != ctx.settlement_id:
			return {"ok": false, "reason": "cross_settlement_villager"}
		if v.active_job_id.is_empty():
			if not v.workplace_id.is_empty() or v.role != SettlementVillagerDataScript.ROLE_IDLE:
				return {"ok": false, "reason": "unassigned_villager_has_stale_workplace_or_role"}
			continue
		if v.life_state != SettlementVillagerDataScript.LIFE_ALIVE:
			return {"ok": false, "reason": "non_alive_villager_has_active_job"}
		if seen_job_to_villager.has(v.active_job_id):
			return {"ok": false, "reason": "multiple_villagers_assigned_to_same_job"}
		var j = ctx.job_board.get_job(v.active_job_id)
		if j == null:
			return {"ok": false, "reason": "villager_references_missing_job"}
		if j.settlement_id != ctx.settlement_id:
			return {"ok": false, "reason": "villager_references_cross_settlement_job"}
		if j.assigned_villager_id != v.villager_id:
			return {"ok": false, "reason": "job_assigned_villager_mismatch"}
		if v.workplace_id.is_empty() or v.workplace_id != j.workplace_id:
			return {"ok": false, "reason": "villager_workplace_id_mismatch"}
		if v.role != j.job_type:
			return {"ok": false, "reason": "villager_role_mismatch"}
		var wp = ctx.workplace_registry.get_workplace(v.workplace_id)
		if wp == null:
			return {"ok": false, "reason": "villager_references_missing_workplace"}
		var is_valid_wp_id: bool = (wp.workplace_id == wp.building_id) or (
			wp.output_resource == EconomyConfigScript.RES_RAW_MEAT
			and wp.workplace_id == ("%s__hunter" % wp.building_id)
		)
		if wp.settlement_id != ctx.settlement_id or wp.building_id.is_empty() or not is_valid_wp_id:
			return {"ok": false, "reason": "workplace_building_id_mismatch"}
		if not wp.is_active or wp.worker_quota <= 0:
			return {"ok": false, "reason": "villager_assigned_to_inactive_or_zero_quota_workplace"}
		seen_job_to_villager[j.job_id] = v.villager_id
		seen_villager_to_job[v.villager_id] = j.job_id
		workers_per_wp[wp.workplace_id] = int(workers_per_wp.get(wp.workplace_id, 0)) + 1
		if int(workers_per_wp[wp.workplace_id]) > int(wp.worker_quota):
			return {"ok": false, "reason": "workplace_worker_quota_exceeded"}

	for j in jobs:
		if j.settlement_id != ctx.settlement_id:
			return {"ok": false, "reason": "cross_settlement_job"}
		if not j.assigned_villager_id.is_empty():
			if not ctx.has_villager(j.assigned_villager_id):
				return {"ok": false, "reason": "job_references_missing_villager"}
			var assigned_v = ctx.get_villager(j.assigned_villager_id)
			if assigned_v.active_job_id != j.job_id:
				return {"ok": false, "reason": "job_villager_bijection_broken"}

	return {
		"ok": true,
		"assigned_pairs": seen_villager_to_job.size(),
		"workers_per_workplace": workers_per_wp
	}
