class_name RivalInspectionQuery
extends RefCounted
## Phase 7 Read-Only Inspection Query & Fog-of-War Gating Adapter.
## Produces detached plain Dictionary/Array view-models for HUD panels.
## Never returns mutable SettlementVillagerData, SettlementEconomy, JobBoard,
## WorkplaceRegistry, SettlementData, or Node/Actor references.

const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const FACTION_LABELS: Dictionary = {
	"neutral_tribe": "Bộ Lạc Trung Lập",
	"rival_military": "Quân Phiệt Địch",
	"rival_merchant": "Thương Hội Địch",
}

const ROLE_LABELS: Dictionary = {
	"idle": "Cư dân rảnh",
	"farmer": "Nông dân",
	"woodcutter": "Thợ đốn gỗ",
	"smith": "Thợ rèn",
	"hauler": "Phu khuân vác",
	"guard": "Lính gác",
	"hunter": "Thợ săn",
}

const TASK_LABELS: Dictionary = {
	"idle": "Đang nhàn rỗi",
	"moving_to_job": "Đang đi làm",
	"working": "Đang làm việc",
	"hauling": "Đang vận chuyển",
	"seeking_food": "Đang tìm thức ăn",
	"resting": "Đang nghỉ ngơi",
	"guarding": "Đang tuần tra / canh gác",
}

const REST_LABELS: Dictionary = {
	"none": "Hoạt động ngoài trời",
	"returning_home": "Đang về nhà",
	"resting_inside": "Đang nghỉ trong nhà",
}

const LIFE_LABELS: Dictionary = {
	"alive": "Còn sống",
	"dead": "Đã mất",
	"removed": "Đã rời đi",
}

const BUILDING_LABELS: Dictionary = {
	"townhall": "Nhà Chính",
	"house": "Nhà Ở",
	"farm": "Nông Trại",
	"woodcutter": "Xưởng Đốn Gỗ",
	"storehouse": "Kho Chứa",
	"barracks": "Doanh Trại",
	"watchtower": "Tháp Canh",
	"market": "Chợ",
	"workshop": "Xưởng Rèn",
	"mine": "Mỏ",
	"quarry": "Mỏ Đá",
}

const SURVIVAL_LABELS: Dictionary = {
	"normal": "Ổn định",
	"shortfall": "Thiếu lương thực",
	"recovery": "Đang hồi phục",
}

const RESOURCE_LABELS: Dictionary = {
	"food": "Lương thực",
	"raw_meat": "Thịt sống",
	"wood": "Gỗ",
	"stone": "Đá",
	"ore": "Quặng",
	"metal": "Kim loại",
	"tools": "Công cụ",
	"herbs": "Thảo dược",
	"crystal": "Pha lê",
	"hearty_meal": "Bữa ăn thịnh soạn",
	"herbal_broth": "Canh thảo dược",
}

var sim_manager: Node = null
var world_data: RefCounted = null
var fog_of_war: RefCounted = null
var presentation_ctrl: Node = null
var debug_fog_disabled: bool = false

func _init(
	p_sim_manager: Node = null,
	p_world_data: RefCounted = null,
	p_fog_of_war: RefCounted = null,
	p_presentation_ctrl: Node = null,
	p_debug_fog_disabled: bool = false
) -> void:
	sim_manager = p_sim_manager
	world_data = p_world_data
	fog_of_war = p_fog_of_war
	presentation_ctrl = p_presentation_ctrl
	debug_fog_disabled = p_debug_fog_disabled

func configure(
	p_sim_manager: Node,
	p_world_data: RefCounted,
	p_fog_of_war: RefCounted,
	p_presentation_ctrl: Node = null,
	p_debug_fog_disabled: bool = false
) -> void:
	sim_manager = p_sim_manager
	world_data = p_world_data
	fog_of_war = p_fog_of_war
	presentation_ctrl = p_presentation_ctrl
	debug_fog_disabled = p_debug_fog_disabled

func _is_debug_reveal() -> bool:
	return debug_fog_disabled and OS.is_debug_build()

func is_cell_explored(cell: Vector2i) -> bool:
	if _is_debug_reveal():
		return true
	if fog_of_war == null:
		return false
	return bool(fog_of_war.is_explored(cell))

func is_cell_visible(cell: Vector2i) -> bool:
	if _is_debug_reveal():
		return true
	if fog_of_war == null:
		return false
	return bool(fog_of_war.is_visible(cell))

func _find_settlement_data(settlement_id: String) -> RefCounted:
	if world_data == null or world_data.get("settlements") == null:
		return null
	for stl in world_data.settlements:
		if stl != null and String(stl.get("settlement_id")) == settlement_id:
			return stl
	return null

func _get_building_cells(b: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var origin: Vector2i = b.get("cell", Vector2i(-1, -1))
	var b_size: Vector2i = b.get("size", Vector2i.ONE)
	if origin.x < 0 or origin.y < 0:
		return cells
	for ox in range(maxi(1, b_size.x)):
		for oy in range(maxi(1, b_size.y)):
			cells.append(origin + Vector2i(ox, oy))
	return cells

func _is_building_explored(b: Dictionary) -> bool:
	for c in _get_building_cells(b):
		if is_cell_explored(c):
			return true
	return false

func _is_building_visible(b: Dictionary) -> bool:
	for c in _get_building_cells(b):
		if is_cell_visible(c):
			return true
	return false

func get_settlement_fog_state(settlement_id: String) -> String:
	var stl := _find_settlement_data(settlement_id)
	if stl == null:
		return "unexplored"
	var anchor: Vector2i = stl.anchor_cell
	if anchor.x >= 0 and anchor.y >= 0 and is_cell_visible(anchor):
		return "visible"
	for b in stl.buildings:
		if _is_building_visible(b):
			return "visible"
	if anchor.x >= 0 and anchor.y >= 0 and is_cell_explored(anchor):
		return "explored"
	for b in stl.buildings:
		if _is_building_explored(b):
			return "explored"
	return "unexplored"

static func format_faction_label(faction_id: String) -> String:
	return String(FACTION_LABELS.get(faction_id, faction_id.capitalize()))

static func format_settlement_display_name(origin_faction_id: String, role: String) -> String:
	var f_label := format_faction_label(origin_faction_id)
	match role:
		SettlementDataScript.ROLE_CAPITAL:
			return "%s — Thủ Phủ" % f_label
		SettlementDataScript.ROLE_VILLAGE:
			return "%s — Làng" % f_label
		SettlementDataScript.ROLE_OUTPOST:
			return "%s — Tiền Đồn" % f_label
		_:
			return f_label

static func format_role_label(role_id: String) -> String:
	return String(ROLE_LABELS.get(role_id, role_id.capitalize()))

static func format_building_label(b_type: String) -> String:
	return String(BUILDING_LABELS.get(b_type, b_type.capitalize()))

static func format_villager_display_name(villager: RefCounted, fallback_index: int = 1) -> String:
	if villager == null:
		return "Cư dân"
	var raw_name: String = String(villager.villager_name).strip_edges()
	var vid: String = String(villager.villager_id)
	var sid: String = String(villager.settlement_id)
	if not raw_name.is_empty() and raw_name != vid:
		return raw_name
	var seq: int = SettlementVillagerDataScript.parse_villager_sequence_for_settlement(vid, sid)
	var num: int = seq if seq >= 1 else maxi(1, fallback_index)
	return "%s #%d" % [format_role_label(String(villager.role)), num]

func _is_villager_individually_visible(v: RefCounted) -> bool:
	if v == null:
		return false
	if String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
		return false
	if String(v.rest_phase) == SettlementVillagerDataScript.REST_RESTING_INSIDE:
		return false
	return is_cell_visible(v.cell)

func get_visible_resident_summaries(settlement_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sim_manager == null or not sim_manager.has_method("get_context"):
		return out
	var ctx = sim_manager.get_context(settlement_id)
	if ctx == null:
		return out
	var all_v: Array = ctx.get_all_villagers()
	var sorted_v: Array = all_v.duplicate()
	sorted_v.sort_custom(func(a, b):
		var sa: int = SettlementVillagerDataScript.parse_villager_sequence_for_settlement(String(a.villager_id), settlement_id)
		var sb: int = SettlementVillagerDataScript.parse_villager_sequence_for_settlement(String(b.villager_id), settlement_id)
		if sa != sb and sa >= 0 and sb >= 0:
			return sa < sb
		return String(a.villager_id) < String(b.villager_id)
	)
	var idx: int = 0
	for v in sorted_v:
		idx += 1
		if not _is_villager_individually_visible(v):
			continue
		out.append({
			"settlement_id": settlement_id,
			"villager_id": String(v.villager_id),
			"display_name": format_villager_display_name(v, idx),
			"role": String(v.role),
			"role_label": format_role_label(String(v.role)),
			"task_state": String(v.task_state),
			"task_label": String(TASK_LABELS.get(String(v.task_state), String(v.task_state))),
			"cell": Vector2i(v.cell.x, v.cell.y),
		})
	return out

func build_settlement_view_model(settlement_id: String) -> Dictionary:
	if settlement_id.is_empty():
		return {"allowed": false, "fog_state": "unexplored", "settlement_id": ""}
	var stl := _find_settlement_data(settlement_id)
	if stl == null:
		return {"allowed": false, "fog_state": "unexplored", "settlement_id": settlement_id}

	var fog_state := get_settlement_fog_state(settlement_id)
	if fog_state == "unexplored":
		return {"allowed": false, "fog_state": "unexplored", "settlement_id": settlement_id}

	var origin_faction: String = String(stl.origin_faction_id)
	var stl_role: String = String(stl.role)
	var stl_tier: String = String(stl.layout_tier)
	var display_name := format_settlement_display_name(origin_faction, stl_role)

	# EXPLORED (not currently VISIBLE): static explored buildings & immutable origin identity only.
	if fog_state == "explored":
		var explored_buildings: Array[Dictionary] = []
		var type_counts: Dictionary = {}
		for b in stl.buildings:
			if not _is_building_explored(b):
				continue
			var b_type: String = String(b.get("type", ""))
			var b_origin: Vector2i = b.get("cell", Vector2i(-1, -1))
			var b_size: Vector2i = b.get("size", Vector2i.ONE)
			explored_buildings.append({
				"type": b_type,
				"type_label": format_building_label(b_type),
				"cell": Vector2i(b_origin.x, b_origin.y),
				"size": Vector2i(b_size.x, b_size.y),
			})
			type_counts[b_type] = int(type_counts.get(b_type, 0)) + 1
		return {
			"allowed": true,
			"fog_state": "explored",
			"is_live_visible": false,
			"settlement_id": settlement_id,
			"origin_faction_id": origin_faction,
			"faction_label": format_faction_label(origin_faction),
			"display_name": display_name,
			"role": stl_role,
			"layout_tier": stl_tier,
			"anchor_cell": Vector2i(stl.anchor_cell.x, stl.anchor_cell.y),
			"explored_building_count": explored_buildings.size(),
			"explored_buildings": explored_buildings,
			"explored_building_type_counts": type_counts,
			"hidden_notice": "Ngoài tầm nhìn trực tiếp — dân số, kinh tế và danh sách cư dân đang bị ẩn.",
		}

	# VISIBLE: full read-only snapshot from canonical SettlementVillagerContext & SettlementEconomy.
	var ctx = sim_manager.get_context(settlement_id) if (sim_manager != null and sim_manager.has_method("get_context")) else null
	var owner_faction: String = String(stl.owner_faction_id)
	var stl_status: String = String(stl.status)

	var living_count: int = 0
	var total_count: int = 0
	var idle_count: int = 0
	var working_count: int = 0
	var resting_count: int = 0
	var role_counts: Dictionary = {}
	if ctx != null:
		for v in ctx.get_all_villagers():
			if v == null or String(v.life_state) == SettlementVillagerDataScript.LIFE_REMOVED:
				continue
			total_count += 1
			if String(v.life_state) == SettlementVillagerDataScript.LIFE_ALIVE:
				living_count += 1
				var r_id: String = String(v.role)
				role_counts[r_id] = int(role_counts.get(r_id, 0)) + 1
				if r_id == SettlementVillagerDataScript.ROLE_IDLE:
					idle_count += 1
				if String(v.rest_phase) != SettlementVillagerDataScript.REST_NONE or String(v.task_state) == SettlementVillagerDataScript.TASK_RESTING:
					resting_count += 1
				elif String(v.task_state) in [
					SettlementVillagerDataScript.TASK_WORKING,
					SettlementVillagerDataScript.TASK_HAULING,
					SettlementVillagerDataScript.TASK_GUARDING,
					SettlementVillagerDataScript.TASK_MOVING_TO_JOB,
				]:
					working_count += 1

	var housing_cap: int = int(ctx.get_housing_capacity()) if ctx != null else 0
	var housing_avail: int = int(ctx.get_available_housing_slots()) if ctx != null else 0
	var housing_occ: int = maxi(0, housing_cap - housing_avail)
	var res_buildings: Array = ctx.get_residential_buildings() if ctx != null else []

	var buildings_out: Array[Dictionary] = []
	for b in stl.buildings:
		var bid: String = String(b.get("id", ""))
		var btype: String = String(b.get("type", ""))
		var b_origin: Vector2i = b.get("cell", Vector2i(-1, -1))
		var b_size: Vector2i = b.get("size", Vector2i.ONE)
		var b_entry: Dictionary = {
			"id": bid,
			"type": btype,
			"type_label": format_building_label(btype),
			"cell": Vector2i(b_origin.x, b_origin.y),
			"size": Vector2i(b_size.x, b_size.y),
			"role": String(b.get("role", "")),
			"is_residential": (btype == "house" or btype == "townhall"),
		}
		if ctx != null and ctx.workplace_registry != null:
			var wp = ctx.workplace_registry.get_workplace(bid)
			if wp == null and btype == "townhall":
				wp = ctx.workplace_registry.get_workplace("%s__hunter" % bid)
			if wp != null:
				var assigned_cnt: int = 0
				if ctx.job_board != null and ctx.job_board.has_method("get_all_jobs"):
					for j in ctx.job_board.get_all_jobs():
						if j != null and String(j.workplace_id) == String(wp.workplace_id) and not String(j.assigned_villager_id).is_empty():
							assigned_cnt += 1
				b_entry["workplace"] = {
					"workplace_id": String(wp.workplace_id),
					"worker_quota": int(wp.worker_quota),
					"assigned_count": assigned_cnt,
					"is_active": bool(wp.is_active),
					"is_paused": bool(wp.is_paused),
					"pause_reason": String(wp.pause_reason),
					"buffer_amount": int(wp.buffer_amount),
					"buffer_capacity": int(wp.buffer_capacity),
				}
		buildings_out.append(b_entry)

	var gold_amt: int = 0
	var gold_cap: int = 0
	var res_list: Array[Dictionary] = []
	if ctx != null and ctx.economy != null:
		gold_amt = int(ctx.economy.get_gold())
		gold_cap = int(ctx.economy.get_gold_capacity())
		var all_res: Dictionary = ctx.economy.get_all_resources()
		var all_caps: Dictionary = ctx.economy.get_all_capacities()
		for res_id in SettlementEconomyScript.PHYSICAL_RESOURCES:
			var amt: int = int(all_res.get(res_id, 0))
			var cap: int = int(all_caps.get(res_id, 0))
			if amt > 0 or res_id == EconomyConfigScript.RES_FOOD:
				res_list.append({
					"id": String(res_id),
					"label": String(RESOURCE_LABELS.get(res_id, String(res_id).capitalize())),
					"amount": amt,
					"capacity": cap,
				})

	var survival_state: String = "normal"
	var ration_shortfall: bool = false
	var recovery_hours_left: int = 0
	var immigrants_admitted: int = 0
	if ctx != null and ctx.sim_state != null:
		survival_state = String(ctx.sim_state.survival_state)
		ration_shortfall = bool(ctx.sim_state.ration_shortfall)
		recovery_hours_left = int(ctx.sim_state.recovery_hours_left)
		immigrants_admitted = int(ctx.sim_state.total_immigrants_admitted)

	return {
		"allowed": true,
		"fog_state": "visible",
		"is_live_visible": true,
		"settlement_id": settlement_id,
		"origin_faction_id": origin_faction,
		"owner_faction_id": owner_faction,
		"faction_label": format_faction_label(owner_faction),
		"display_name": display_name,
		"role": stl_role,
		"status": stl_status,
		"layout_tier": stl_tier,
		"anchor_cell": Vector2i(stl.anchor_cell.x, stl.anchor_cell.y),
		"living_count": living_count,
		"total_count": total_count,
		"idle_count": idle_count,
		"working_count": working_count,
		"resting_count": resting_count,
		"role_counts": role_counts.duplicate(true),
		"housing_capacity": housing_cap,
		"housing_available": housing_avail,
		"housing_occupied": housing_occ,
		"residential_building_count": res_buildings.size(),
		"buildings": buildings_out,
		"gold": gold_amt,
		"gold_capacity": gold_cap,
		"resources": res_list,
		"survival_state": survival_state,
		"survival_label": String(SURVIVAL_LABELS.get(survival_state, survival_state.capitalize())),
		"ration_shortfall": ration_shortfall,
		"recovery_hours_left": recovery_hours_left,
		"total_immigrants_admitted": immigrants_admitted,
		"visible_residents": get_visible_resident_summaries(settlement_id),
	}

func build_villager_view_model(settlement_id: String, villager_id: String) -> Dictionary:
	if settlement_id.is_empty() or villager_id.is_empty():
		return {"allowed": false, "reason": "invalid_identity"}
	if sim_manager == null or not sim_manager.has_method("get_context"):
		return {"allowed": false, "reason": "missing_sim_manager"}
	var ctx = sim_manager.get_context(settlement_id)
	if ctx == null:
		return {"allowed": false, "reason": "missing_settlement"}
	var v = ctx.get_villager(villager_id)
	if v == null:
		return {"allowed": false, "reason": "missing_villager"}
	if not _is_villager_individually_visible(v):
		return {"allowed": false, "reason": "not_visible"}

	var stl := _find_settlement_data(settlement_id)
	var stl_name: String = format_settlement_display_name(
		String(v.origin_faction_id),
		String(stl.role) if stl != null else "capital"
	)

	var home_label: String = "Chưa có"
	if not String(v.home_building_id).is_empty() and stl != null:
		home_label = _resolve_building_label_in_stl(stl, String(v.home_building_id))

	var workplace_label: String = "Không có"
	if not String(v.workplace_id).is_empty():
		if ctx.workplace_registry != null:
			var wp = ctx.workplace_registry.get_workplace(String(v.workplace_id))
			if wp != null:
				workplace_label = format_building_label(String(wp.building_type))
		elif stl != null:
			workplace_label = _resolve_building_label_in_stl(stl, String(v.workplace_id))

	var has_pres_nav: bool = false
	var is_moving_pres: bool = false
	var dest_cell_pres: Vector2i = Vector2i(-1, -1)
	var pres_state_label: String = "Đứng yên (hiển thị)"
	if presentation_ctrl != null and presentation_ctrl.has_method("get_navigation_context"):
		var nav_ctx = presentation_ctrl.get_navigation_context(settlement_id)
		if nav_ctx != null and nav_ctx.has_method("has_locomotion") and bool(nav_ctx.has_locomotion(villager_id)):
			var loco = nav_ctx.get_or_create_locomotion(v)
			if loco != null:
				has_pres_nav = true
				is_moving_pres = bool(loco.is_moving)
				dest_cell_pres = Vector2i(loco.goal_cell.x, loco.goal_cell.y) if loco.get("goal_cell") is Vector2i else Vector2i(-1, -1)
				pres_state_label = "Đang di chuyển (hiển thị)" if is_moving_pres else "Đứng yên (hiển thị)"

	return {
		"allowed": true,
		"settlement_id": settlement_id,
		"villager_id": villager_id,
		"display_name": format_villager_display_name(v),
		"settlement_display_name": stl_name,
		"origin_faction_id": String(v.origin_faction_id),
		"current_faction_id": String(v.current_faction_id),
		"faction_label": format_faction_label(String(v.current_faction_id)),
		"life_state": String(v.life_state),
		"life_label": String(LIFE_LABELS.get(String(v.life_state), String(v.life_state))),
		"role": String(v.role),
		"role_label": format_role_label(String(v.role)),
		"task_state": String(v.task_state),
		"task_label": String(TASK_LABELS.get(String(v.task_state), String(v.task_state))),
		"rest_phase": String(v.rest_phase),
		"rest_label": String(REST_LABELS.get(String(v.rest_phase), String(v.rest_phase))),
		"home_building_id": String(v.home_building_id),
		"home_label": home_label,
		"workplace_id": String(v.workplace_id),
		"workplace_label": workplace_label,
		"active_job_id": String(v.active_job_id),
		"work_target_id": String(v.work_target_id),
		"cell": Vector2i(v.cell.x, v.cell.y),
		"hunger": float(v.hunger),
		"fatigue": float(v.fatigue),
		"health": float(v.health),
		"morale": float(v.morale),
		"has_presentation_nav": has_pres_nav,
		"is_moving": is_moving_pres,
		"dest_cell": dest_cell_pres,
		"presentation_state_label": pres_state_label,
	}

func _resolve_building_label_in_stl(stl: RefCounted, building_id: String) -> String:
	for b in stl.buildings:
		if String(b.get("id", "")) == building_id:
			return format_building_label(String(b.get("type", "")))
	return "Công trình"

func find_rival_target_at_cell(cell: Vector2i, click_world_pos: Vector2 = Vector2.INF) -> Dictionary:
	# 1. Eligible visible Rival Villager (active Near Actor bounds OR canonical visible cell)
	var candidates: Array[Dictionary] = []
	var seen_keys: Dictionary = {}

	if presentation_ctrl != null and presentation_ctrl.has_method("get_actor_pool"):
		var pool = presentation_ctrl.get_actor_pool()
		if pool != null and pool.has_method("get_all_active_keys") and click_world_pos != Vector2.INF:
			for key in pool.get_all_active_keys():
				var parts := String(key).split(":")
				if parts.size() != 2:
					continue
				var sid: String = parts[0]
				var vid: String = parts[1]
				var actor: Node2D = pool.get_active_actor(sid, vid)
				if actor == null or not is_instance_valid(actor) or not actor.visible:
					continue
				var hit_rect := Rect2(actor.position + Vector2(-12.0, -30.0), Vector2(24.0, 32.0))
				var spr: Variant = actor.get("sprite")
				if spr is Sprite2D and (spr as Sprite2D).texture != null:
					var s_rect: Rect2 = (spr as Sprite2D).get_rect()
					hit_rect = Rect2(
						actor.position + s_rect.position * actor.scale,
						s_rect.size * actor.scale
					)
				if hit_rect.has_point(click_world_pos):
					var ctx = sim_manager.get_context(sid) if sim_manager != null else null
					var v = ctx.get_villager(vid) if ctx != null else null
					if _is_villager_individually_visible(v):
						var d2: float = actor.position.distance_squared_to(click_world_pos)
						candidates.append({"sid": sid, "vid": vid, "dist2": d2})
						seen_keys[key] = true

	if sim_manager != null and sim_manager.has_method("get_registered_settlement_ids"):
		for sid in sim_manager.get_registered_settlement_ids():
			var ctx = sim_manager.get_context(sid)
			if ctx == null:
				continue
			for v in ctx.get_all_villagers():
				if not _is_villager_individually_visible(v):
					continue
				var key := "%s:%s" % [sid, String(v.villager_id)]
				if seen_keys.has(key):
					continue
				if v.cell == cell:
					candidates.append({"sid": sid, "vid": String(v.villager_id), "dist2": 0.0})

	if not candidates.is_empty():
		candidates.sort_custom(func(a, b):
			if not is_equal_approx(float(a["dist2"]), float(b["dist2"])):
				return float(a["dist2"]) < float(b["dist2"])
			if String(a["sid"]) != String(b["sid"]):
				return String(a["sid"]) < String(b["sid"])
			return String(a["vid"]) < String(b["vid"])
		)
		return {
			"kind": "villager",
			"settlement_id": String(candidates[0]["sid"]),
			"villager_id": String(candidates[0]["vid"]),
		}

	# 2. Rival Settlement building footprint (requires at least EXPLORED on clicked cell)
	if world_data != null and world_data.get("settlements") != null and is_cell_explored(cell):
		for stl in world_data.settlements:
			if stl == null:
				continue
			for b in stl.buildings:
				var origin: Vector2i = b.get("cell", Vector2i(-1, -1))
				var b_size: Vector2i = b.get("size", Vector2i.ONE)
				if cell.x >= origin.x and cell.x < origin.x + b_size.x and cell.y >= origin.y and cell.y < origin.y + b_size.y:
					return {
						"kind": "settlement",
						"settlement_id": String(stl.settlement_id),
						"building_cell": origin,
						"building_size": b_size,
					}

	return {}
