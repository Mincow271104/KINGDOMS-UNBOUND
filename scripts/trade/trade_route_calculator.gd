class_name TradeRouteCalculator
extends RefCounted
## =============================================================================
## KINGDOMS UNBOUND — Dynamic Trade Route Risk Calculator (Package 3C)
## Conforms to GDD §11.1, §11.2 (Market Pricing, Route Risk & Trade Caravans).
## Strictly evaluates corridor security across Fog of War, territorial outposts,
## and watchtower defenses, returning deterministic and explainable price modifiers.
## =============================================================================

# Authoritative Faction Anchors (Mirrors WorldView setup)
const DEFAULT_MERCHANT_ANCHOR := Vector2i(50, 16)
const DEFAULT_MILITARY_ANCHOR := Vector2i(14, 14)
const DEFAULT_TRIBE_ANCHOR := Vector2i(16, 48)

# Bounded Risk Surcharge Limits (Package 3C Implementation Baseline)
# GDD §11.2 mandates route risk influence without unbounded price spikes or arbitrage.
const MAX_DISCOUNT: float = -0.10     # Max -10% discount for fully secured trade route
const MAX_SURCHARGE: float = 0.25    # Max +25% surcharge for perilous wilderness / wartime
const UNEXPLORED_WEIGHT: float = 0.15 # Up to +15% surcharge for 100% unexplored path
const SECURED_WEIGHT: float = 0.10    # Up to -10% discount for 100% player outpost/watchtower coverage
const HOSTILE_WEIGHT: float = 0.10    # Up to +10% surcharge for enemy outpost interception zone
const WARTIME_WEIGHT: float = 0.10    # +10% surcharge if merchant origin faction is at war

## Computes discrete grid cells connecting start and end using standard Bresenham line traversal.
## Guaranteed deterministic, symmetric, bounded, and allocation-friendly.
static func compute_route_cells(start_cell: Vector2i, end_cell: Vector2i) -> Array[Vector2i]:
	if not IsoMath.is_in_bounds(start_cell) or not IsoMath.is_in_bounds(end_cell):
		return []
	if start_cell == end_cell:
		return [start_cell]

	var cells: Array[Vector2i] = []
	var x0 := start_cell.x
	var y0 := start_cell.y
	var x1 := end_cell.x
	var y1 := end_cell.y

	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy

	while true:
		if IsoMath.is_in_bounds(Vector2i(x0, y0)):
			cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

	return cells

## Resolves the origin cell for a merchant caravan based on faction outpost or default anchor.
static func get_caravan_origin_cell(origin_faction: String, field_siege_mgr: Object = null, _world_seed: int = 0) -> Vector2i:
	if field_siege_mgr != null and is_instance_valid(field_siege_mgr) and field_siege_mgr.has_method("get_all_objectives"):
		var raw_objs = field_siege_mgr.get_all_objectives()
		if raw_objs is Array:
			for obj in raw_objs:
				if obj != null and is_instance_valid(obj):
					var fid: String = str(obj.get("owning_faction_id"))
					if fid == origin_faction:
						var is_alive: bool = bool(obj.get("is_alive")) if obj.get("is_alive") != null else true
						var hp: float = float(obj.get("health")) if obj.get("health") != null else 0.0
						if is_alive and hp > 0.0:
							var o_cell = obj.get("current_cell")
							if o_cell is Vector2i and IsoMath.is_in_bounds(o_cell):
								return o_cell

	match origin_faction:
		"rival_military":
			return DEFAULT_MILITARY_ANCHOR
		"neutral_tribe":
			return DEFAULT_TRIBE_ANCHOR
		"rival_merchant", _:
			return DEFAULT_MERCHANT_ANCHOR

## Evaluates the route risk across an array of route cells.
## Evaluates:
## 1. Unexplored Fog of War ratio (wilderness hazard)
## 2. Player defensive coverage (player outposts [r=6] + watchtowers [r=15])
## 3. Hostile outpost interception (enemy outposts [r=6])
## 4. Origin faction wartime status
static func evaluate_route_risk(
	route_cells: Array,
	fow: Object = null,
	field_siege_mgr: Object = null,
	world_data: Variant = null,
	is_origin_at_war: bool = false,
	world_modifiers: Variant = [],
	conservative_empty_fallback: bool = false
) -> Dictionary:
	var safe_modifiers: Array = world_modifiers if (world_modifiers != null and world_modifiers is Array) else []
	var has_bandits: bool = safe_modifiers.has("restless_bandits")

	var valid_cells: Array[Vector2i] = []
	var has_input_cells: bool = false
	if route_cells != null and route_cells is Array:
		has_input_cells = route_cells.size() > 0
		for item in route_cells:
			if item is Vector2i and IsoMath.is_in_bounds(item):
				valid_cells.append(item)

	var total_cells := valid_cells.size()

	# Empty corridor fallback (Work Item C §6.3)
	# Triggered if endpoints/corridor cells are invalid or explicitly flagged for conservative fallback.
	if total_cells == 0:
		var apply_fallback: bool = conservative_empty_fallback or (has_input_cells and total_cells == 0)
		var war_only: float = WARTIME_WEIGHT if is_origin_at_war else 0.0
		var mod_only: float = 0.10 if has_bandits else 0.0
		var base_wilderness: float = UNEXPLORED_WEIGHT if apply_fallback else 0.0
		var raw_only: float = base_wilderness + war_only + mod_only
		var zero_reasons: Array = []
		if apply_fallback:
			zero_reasons.append("unexplored")
		if is_origin_at_war:
			zero_reasons.append("wartime")
		if has_bandits:
			zero_reasons.append("restless_bandits")
		return {
			"total_cells": 0,
			"unexplored_cells": 0,
			"unexplored_ratio": 1.0 if apply_fallback else 0.0,
			"secured_cells": 0,
			"secured_ratio": 0.0,
			"hostile_cells": 0,
			"hostile_ratio": 0.0,
			"is_origin_at_war": is_origin_at_war,
			"wartime_factor": war_only,
			"raw_risk": raw_only,
			"net_risk": clampf(raw_only, MAX_DISCOUNT, MAX_SURCHARGE),
			"world_modifiers": safe_modifiers.duplicate(),
			"reasons": zero_reasons
		}

	# Gather living player outposts and active enemy outposts (Work Item C §6.4)
	var player_outposts: Array[Dictionary] = []
	var hostile_outposts: Array[Dictionary] = []
	if field_siege_mgr != null and is_instance_valid(field_siege_mgr) and field_siege_mgr.has_method("get_all_objectives"):
		var raw_objs = field_siege_mgr.get_all_objectives()
		if raw_objs is Array:
			for obj in raw_objs:
				if obj != null and is_instance_valid(obj):
					var is_alive: bool = bool(obj.get("is_alive")) if obj.get("is_alive") != null else true
					var hp: float = float(obj.get("health")) if obj.get("health") != null else 0.0
					if is_alive and hp > 0.0:
						var o_cell = obj.get("current_cell")
						if o_cell is Vector2i and IsoMath.is_in_bounds(o_cell):
							var o_rad: int = int(obj.get("vision_radius")) if obj.get("vision_radius") != null else 6
							var fid: String = str(obj.get("owning_faction_id"))
							if fid == "player":
								player_outposts.append({"cell": o_cell, "radius": o_rad})
							elif fid != "neutral_tribe" and not fid.is_empty():
								hostile_outposts.append({"cell": o_cell, "radius": 6})

	# Gather active player watchtowers from world_data (Work Item C §6.4)
	var player_watchtowers: Array[Dictionary] = []
	if world_data != null:
		var raw_buildings = null
		if world_data is Dictionary:
			raw_buildings = world_data.get("buildings")
		elif world_data is Object and is_instance_valid(world_data):
			raw_buildings = world_data.get("buildings")
		if raw_buildings is Array:
			for b in raw_buildings:
				if b is Dictionary:
					var b_type = b.get("type")
					var b_state = b.get("state", "active")
					var b_hp = b.get("health", 100.0)
					if b_type == "watchtower" and b_state == "active" and (b_hp == null or float(b_hp) > 0.0):
						var b_cell = b.get("cell")
						if b_cell is Vector2i and IsoMath.is_in_bounds(b_cell):
							var bp: Dictionary = EconomyConfig.BLUEPRINTS.get("watchtower", {}) if ("BLUEPRINTS" in EconomyConfig) else {}
							var v_rad: int = bp.get("vision_radius", 15)
							player_watchtowers.append({"cell": b_cell, "radius": v_rad})

	var has_valid_fow: bool = fow != null and is_instance_valid(fow) and fow.has_method("is_unexplored")
	var unexplored_count := 0
	var secured_count := 0
	var hostile_count := 0

	for cell in valid_cells:
		# 1. Fog of War Check (Work Item C §6.2: Conservative fallback if FOW is null/missing)
		if has_valid_fow:
			if fow.is_unexplored(cell):
				unexplored_count += 1
		else:
			unexplored_count += 1

		# 2. Player Security Check (Work Item B: Unique-cell friendly coverage)
		var is_sec := false
		for po in player_outposts:
			var poc: Vector2i = po["cell"]
			if absi(cell.x - poc.x) + absi(cell.y - poc.y) <= po["radius"]:
				is_sec = true
				break
		if not is_sec:
			for pwt in player_watchtowers:
				var wtc: Vector2i = pwt["cell"]
				if absi(cell.x - wtc.x) + absi(cell.y - wtc.y) <= pwt["radius"]:
					is_sec = true
					break
		if is_sec:
			secured_count += 1

		# 3. Hostile Outpost Interception Check (Work Item B: Unique-cell hostile coverage)
		var is_host := false
		for ho in hostile_outposts:
			var hoc: Vector2i = ho["cell"]
			if absi(cell.x - hoc.x) + absi(cell.y - hoc.y) <= ho["radius"]:
				is_host = true
				break
		if is_host:
			hostile_count += 1

	var u_ratio := float(unexplored_count) / float(total_cells)
	var s_ratio := float(secured_count) / float(total_cells)
	var h_ratio := float(hostile_count) / float(total_cells)
	var war_val := WARTIME_WEIGHT if is_origin_at_war else 0.0
	var mod_risk: float = 0.10 if has_bandits else 0.0

	var raw_risk := (UNEXPLORED_WEIGHT * u_ratio) - (SECURED_WEIGHT * s_ratio) + (HOSTILE_WEIGHT * h_ratio) + war_val + mod_risk
	var net_risk := clampf(raw_risk, MAX_DISCOUNT, MAX_SURCHARGE)

	var reasons: Array = []
	if unexplored_count > 0:
		reasons.append("unexplored")
	if secured_count > 0:
		reasons.append("secured")
	if hostile_count > 0:
		reasons.append("hostile_outpost")
	if is_origin_at_war:
		reasons.append("wartime")
	if has_bandits:
		reasons.append("restless_bandits")

	return {
		"total_cells": total_cells,
		"unexplored_cells": unexplored_count,
		"unexplored_ratio": u_ratio,
		"secured_cells": secured_count,
		"secured_ratio": s_ratio,
		"hostile_cells": hostile_count,
		"hostile_ratio": h_ratio,
		"is_origin_at_war": is_origin_at_war,
		"wartime_factor": war_val,
		"raw_risk": raw_risk,
		"net_risk": net_risk,
		"world_modifiers": safe_modifiers.duplicate(),
		"reasons": reasons
	}

static func evaluate_route_risk_between(
	origin: Vector2i,
	destination: Vector2i,
	fow: Object = null,
	field_siege_mgr: Object = null,
	world_data: Variant = null,
	is_origin_at_war: bool = false,
	world_modifiers: Variant = []
) -> Dictionary:
	var route := compute_route_cells(origin, destination)
	return evaluate_route_risk(route, fow, field_siege_mgr, world_data, is_origin_at_war, world_modifiers, route.is_empty())
