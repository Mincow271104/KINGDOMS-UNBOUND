class_name WorkerPresentationResolver
extends RefCounted
## M3-0 Read-Only Worker Presentation Resolver.
## Derives transient presentation metadata from canonical SettlementVillagerData,
## SettlementJobBoard, SettlementWorkplaceRegistry, SettlementNavigationContext,
## and WorldData without mutating any simulation or navigation state.

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementNavigationContextScript = preload("res://scripts/world/settlement_navigation_context.gd")
const SettlementResourceSourceAdapterScript = preload("res://scripts/world/settlement_resource_source_adapter.gd")
const ContinuousPathFollowerScript = preload("res://scripts/navigation/continuous_path_follower.gd")

enum State {
	NONE = 0,
	APPROACHING = 1,
	WORKING_AT_TARGET = 2,
	WAITING = 3,
	TRANSPORT_EMPTY = 4,
	TRANSPORT_LOADED = 5,
	GUARDING = 6,
	RETURNING_HOME = 7,
	RESTING = 8,
	INVALID_TARGET = 9,
}

class PresentationResult extends RefCounted:
	var presentation_state: int = State.NONE
	var is_moving: bool = false
	var has_valid_focus: bool = false
	var focus_cell: Vector2i = Vector2i(-1, -1)
	var facing_dir: int = ContinuousPathFollowerScript.ScreenDir.E
	var flip_h: bool = false
	var transport_loaded: bool = false
	var cargo_resource: String = ""

	func reset() -> void:
		presentation_state = State.NONE
		is_moving = false
		has_valid_focus = false
		focus_cell = Vector2i(-1, -1)
		facing_dir = ContinuousPathFollowerScript.ScreenDir.E
		flip_h = false
		transport_loaded = false
		cargo_resource = ""

func resolve(
	ctx: RefCounted,
	villager: RefCounted,
	loc: RefCounted,
	world_data: RefCounted = null,
	time_manager: Node = null
) -> PresentationResult:
	var out := PresentationResult.new()
	resolve_into(ctx, villager, loc, world_data, time_manager, out)
	return out

func resolve_into(
	ctx: RefCounted,
	villager: RefCounted,
	loc: RefCounted,
	world_data: RefCounted,
	time_manager: Node,
	out: PresentationResult
) -> void:
	if out == null:
		return
	out.reset()
	if villager == null:
		return
	if String(villager.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
		return

	var base_facing: int = loc.facing_dir if loc != null else ContinuousPathFollowerScript.ScreenDir.E
	var base_flip: bool = loc.flip_h if loc != null else false
	var loc_moving: bool = (loc != null and bool(loc.is_moving))
	var loc_arrived: bool = (loc != null and int(loc.status) == SettlementNavigationContextScript.MoveStatus.ARRIVED)

	out.facing_dir = base_facing
	out.flip_h = base_flip
	out.is_moving = loc_moving

	var t_state: String = String(villager.task_state)
	var r_phase: String = String(villager.rest_phase)

	# 1. Resting / Returning Home
	if r_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE:
		out.presentation_state = State.RESTING
		out.is_moving = false
		return
	if t_state == SettlementVillagerDataScript.TASK_RESTING or r_phase == SettlementVillagerDataScript.REST_RETURNING_HOME:
		out.presentation_state = State.RETURNING_HOME
		if loc != null and bool(loc.has_valid_focus):
			out.has_valid_focus = true
			out.focus_cell = loc.focus_cell
		return

	# 2. Job lookup
	var j_id: String = String(villager.active_job_id)
	if j_id.is_empty() or ctx == null or ctx.job_board == null or ctx.workplace_registry == null:
		out.presentation_state = State.NONE
		return

	var job = ctx.job_board.get_job(j_id)
	if job == null or String(job.settlement_id) != String(ctx.settlement_id):
		out.presentation_state = State.INVALID_TARGET
		return

	var wp = ctx.workplace_registry.get_workplace(String(job.workplace_id))
	if wp == null or String(wp.settlement_id) != String(ctx.settlement_id) or not bool(wp.is_active) or int(wp.worker_quota) <= 0:
		out.presentation_state = State.INVALID_TARGET
		return

	var v_role: String = String(villager.role)

	# 3. Hauler (cargo-driven presentation)
	if v_role == SettlementVillagerDataScript.ROLE_HAULER and t_state == SettlementVillagerDataScript.TASK_HAULING:
		var amt: int = villager.get_carrying_amount()
		out.transport_loaded = amt > 0
		out.cargo_resource = villager.get_carrying_resource() if out.transport_loaded else ""
		var haul_focus: Vector2i = loc.focus_cell if (loc != null and bool(loc.has_valid_focus)) else (job.dest_cell if out.transport_loaded else job.source_cell)
		if haul_focus.x < 0 or haul_focus.y < 0:
			haul_focus = job.target_cell
		if haul_focus.x >= 0 and haul_focus.y >= 0:
			out.has_valid_focus = true
			out.focus_cell = haul_focus
			out.presentation_state = State.TRANSPORT_LOADED if out.transport_loaded else State.TRANSPORT_EMPTY
		else:
			out.has_valid_focus = false
			out.focus_cell = Vector2i(-1, -1)
			out.presentation_state = State.INVALID_TARGET
		_apply_focus_facing(villager.cell, out, loc_moving, base_facing, base_flip)
		return

	# 4. Guard (actual patrol targets or Barracks fallback)
	if v_role == SettlementVillagerDataScript.ROLE_GUARD and t_state == SettlementVillagerDataScript.TASK_GUARDING:
		var guard_focus: Vector2i = _resolve_guard_focus(ctx, villager, job)
		if guard_focus.x < 0 or guard_focus.y < 0:
			out.presentation_state = State.INVALID_TARGET
			out.has_valid_focus = false
			out.focus_cell = Vector2i(-1, -1)
			return
		out.has_valid_focus = true
		out.focus_cell = guard_focus
		if bool(wp.is_paused):
			out.presentation_state = State.WAITING
		elif loc_moving:
			out.presentation_state = State.APPROACHING
		elif loc_arrived:
			out.presentation_state = State.GUARDING
		else:
			out.presentation_state = State.WAITING
		_apply_focus_facing(villager.cell, out, loc_moving, base_facing, base_flip)
		return

	# 5. Farmer / Woodcutter / Hunter
	if t_state == SettlementVillagerDataScript.TASK_WORKING or t_state == SettlementVillagerDataScript.TASK_MOVING_TO_JOB:
		var target_focus: Vector2i = _resolve_worker_focus(ctx, villager, job, world_data, loc)
		if target_focus.x < 0 or target_focus.y < 0:
			out.presentation_state = State.INVALID_TARGET
			out.has_valid_focus = false
			out.focus_cell = Vector2i(-1, -1)
			return
		out.has_valid_focus = true
		out.focus_cell = target_focus
		if bool(wp.is_paused):
			out.presentation_state = State.WAITING
			_apply_focus_facing(villager.cell, out, loc_moving, base_facing, base_flip)
			return
		var wpid_str: String = String(wp.workplace_id)
		var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(wpid_str)
		var prod_blocked: bool = (ctx.sim_state != null and ctx.sim_state.production_blocked.has(wpid_str))
		if v_role == SettlementVillagerDataScript.ROLE_WOODCUTTER:
			var headroom: int = maxi(0, eff_cap - int(wp.buffer_amount))
			if headroom < SettlementResourceSourceAdapterScript.TREE_WOOD_UNITS or prod_blocked:
				out.presentation_state = State.WAITING
				_apply_focus_facing(villager.cell, out, loc_moving, base_facing, base_flip)
				return
		elif v_role == SettlementVillagerDataScript.ROLE_FARMER:
			var tm_ref: Node = time_manager
			if tm_ref == null and ctx.has_meta("time_manager"):
				tm_ref = ctx.get_meta("time_manager")
			if int(wp.buffer_amount) >= eff_cap or prod_blocked or SettlementResourceSourceAdapterScript.is_farm_daily_cap_reached(ctx, wpid_str, tm_ref, -1):
				out.presentation_state = State.WAITING
				_apply_focus_facing(villager.cell, out, loc_moving, base_facing, base_flip)
				return
		elif v_role == SettlementVillagerDataScript.ROLE_HUNTER and prod_blocked:
			out.presentation_state = State.WAITING
			_apply_focus_facing(villager.cell, out, loc_moving, base_facing, base_flip)
			return
		if loc_moving:
			out.presentation_state = State.APPROACHING
		elif loc_arrived:
			out.presentation_state = State.WORKING_AT_TARGET
		else:
			out.presentation_state = State.WAITING
		_apply_focus_facing(villager.cell, out, loc_moving, base_facing, base_flip)
		return

	out.presentation_state = State.NONE

static func _resolve_guard_focus(ctx: RefCounted, villager: RefCounted, job: RefCounted) -> Vector2i:
	var wt_id: String = String(villager.work_target_id)
	if ctx.has_method("get_patrol_targets"):
		for pt in ctx.get_patrol_targets():
			if pt is Dictionary and String(pt.get("building_id", "")) == wt_id:
				var ac: Variant = pt.get("access_cell")
				if ac is Vector2i and ac.x >= 0 and ac.y >= 0:
					return ac
	if job.target_cell.x >= 0 and job.target_cell.y >= 0:
		return job.target_cell
	return Vector2i(-1, -1)

static func _resolve_worker_focus(ctx: RefCounted, villager: RefCounted, job: RefCounted, world_data: RefCounted, loc: RefCounted) -> Vector2i:
	var v_role: String = String(villager.role)
	var wpid: String = String(job.workplace_id)
	var st: RefCounted = ctx.sim_state
	if v_role == SettlementVillagerDataScript.ROLE_HUNTER:
		if st != null and st.production_sources.has(wpid):
			var src: Variant = st.production_sources[wpid]
			if src is Dictionary:
				var prey_id: String = String(src.get("current_prey_id", ""))
				if not prey_id.is_empty() and world_data != null and world_data.has_method("get_animal_by_id"):
					var animal: Dictionary = world_data.get_animal_by_id(prey_id)
					var is_avail: bool = bool(animal.get("is_available", true))
					var res_by: String = String(animal.get("reserved_by", ""))
					var res_type: String = String(animal.get("reservation_type", ""))
					var rec_left: float = float(animal.get("recovery_hours_left", 0.0))
					var owner_ok: bool = (res_by == villager.villager_id and (res_type == "rival" or res_type.is_empty())) or (is_avail and res_by.is_empty() and res_type.is_empty() and rec_left <= 0.0)
					if not animal.is_empty() and animal.get("cell") is Vector2i and owner_ok:
						return animal["cell"]
		return Vector2i(-1, -1)
	if v_role == SettlementVillagerDataScript.ROLE_WOODCUTTER:
		if st != null and st.production_sources.has(wpid):
			var src_w: Variant = st.production_sources[wpid]
			if src_w is Dictionary and src_w.get("trees") is Array:
				for t in src_w["trees"]:
					if t is Dictionary and int(t.get("remaining_milli", 0)) > 0 and t.get("cell") is Vector2i:
						return t["cell"]
		return Vector2i(-1, -1)
	if loc != null and bool(loc.has_valid_focus) and loc.focus_cell.x >= 0 and loc.focus_cell.y >= 0:
		return loc.focus_cell
	if job.target_cell.x >= 0 and job.target_cell.y >= 0:
		return job.target_cell
	return Vector2i(-1, -1)

static func _apply_focus_facing(
	villager_cell: Vector2i,
	out: PresentationResult,
	loc_moving: bool,
	base_facing: int,
	base_flip: bool
) -> void:
	if loc_moving or not out.has_valid_focus or out.focus_cell == villager_cell:
		out.facing_dir = base_facing
		out.flip_h = base_flip
		return
	var delta_px: Vector2 = IsoMath.map_to_local(out.focus_cell) - IsoMath.map_to_local(villager_cell)
	if delta_px.length_squared() >= 0.001:
		var dir_enum: int = ContinuousPathFollowerScript.classify_screen_direction(delta_px, base_facing)
		out.facing_dir = dir_enum
		out.flip_h = ContinuousPathFollowerScript.should_flip_h(dir_enum, base_flip)
