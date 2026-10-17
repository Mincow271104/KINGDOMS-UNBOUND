class_name ResearchManager
extends RefCounted
## Research Management System for KINGDOMS UNBOUND.
## Manages technology progression, prerequisites, atomic cost deductions, and bonus applications.
## Adheres strictly to GDD 9.3: exactly one active project at a time; pause safety.

signal tech_started(tech_id: String)
signal tech_progress_updated(tech_id: String, progress_hours: float, total_hours: float)
signal tech_completed(tech_id: String)
signal tech_cancelled(tech_id: String, refund: Dictionary)

var _unlocked_techs: Dictionary = {} # tech_id -> bool
var active_tech_id: String = ""
var active_progress_hours: float = 0.0
var active_required_hours: float = 0.0
var hall_checker: Callable = Callable()

func set_hall_checker(checker: Callable) -> void:
	hall_checker = checker

func has_active_hall() -> bool:
	if hall_checker.is_valid():
		return bool(hall_checker.call())
	return false

func is_unlocked(tech_id: String) -> bool:
	return _unlocked_techs.get(tech_id, false)

func get_unlocked_count() -> int:
	return _unlocked_techs.size()

func get_unlocked_tech_ids() -> Array:
	return _unlocked_techs.keys()

func can_research(tech_id: String, resource_mgr: Object) -> Dictionary:
	var def: Dictionary = TechTree.TECHNOLOGIES.get(tech_id, {})
	if def.is_empty():
		return {"valid": false, "reason": "Công nghệ không tồn tại"}
		
	if is_unlocked(tech_id):
		return {"valid": false, "reason": "Công nghệ đã hoàn thành"}
		
	if active_tech_id != "":
		return {"valid": false, "reason": "Đang có dự án nghiên cứu khác: %s" % active_tech_id}
		
	if not has_active_hall():
		return {"valid": false, "reason": "Cần có Viện Nghiên Cứu Hoàng Gia đang hoạt động"}

	for prereq in def.get("prereqs", []):
		if not is_unlocked(prereq):
			var prereq_def = TechTree.TECHNOLOGIES.get(prereq, {})
			var p_name: String = prereq_def.get("name", prereq)
			return {"valid": false, "reason": "Cần hoàn thành tiên quyết: %s" % p_name}
			
	if resource_mgr != null:
		var cost: Dictionary = def.get("cost", {})
		if resource_mgr.has_method("can_afford") and not resource_mgr.can_afford(cost):
			return {"valid": false, "reason": "Không đủ tài nguyên"}
			
	return {"valid": true, "reason": "Hợp lệ"}

func start_research(tech_id: String, resource_mgr: Object) -> bool:
	var check: Dictionary = can_research(tech_id, null)
	if not check["valid"]:
		return false
		
	var def: Dictionary = TechTree.TECHNOLOGIES[tech_id]
	var cost: Dictionary = def.get("cost", {})
	
	# Atomically reserve and commit resources
	if resource_mgr != null and not cost.is_empty():
		if not resource_mgr.has_method("reserve_cost") or not resource_mgr.has_method("commit_cost"):
			return false

		var reserved: bool = resource_mgr.call("reserve_cost", cost)
		if not reserved:
			return false

		resource_mgr.call("commit_cost", cost)

	active_tech_id = tech_id
	active_progress_hours = 0.0
	active_required_hours = def.get("duration_hours", 12.0)
	
	tech_started.emit(tech_id)
	return true

func progress_research(delta_hours: float, resource_mgr: Object = null) -> bool:
	if active_tech_id == "":
		return false
		
	if not has_active_hall():
		return false

	# Crystal Resonance bonus (+25% research speed)
	var speed_mult := 1.0
	if is_unlocked("crystal_resonance"):
		speed_mult = 1.25
		
	active_progress_hours += delta_hours * speed_mult
	tech_progress_updated.emit(active_tech_id, active_progress_hours, active_required_hours)
	
	if active_progress_hours >= active_required_hours:
		_complete_current_research(resource_mgr)
		return true
	return false

func _complete_current_research(resource_mgr: Object) -> void:
	var finished_id: String = active_tech_id
	_unlocked_techs[finished_id] = true
	active_tech_id = ""
	active_progress_hours = 0.0
	active_required_hours = 0.0
	
	var def: Dictionary = TechTree.TECHNOLOGIES.get(finished_id, {})
	var t_name: String = def.get("name", finished_id)
	
	# Apply global tech bonuses
	if finished_id == "reinforced_storage" and resource_mgr != null:
		if resource_mgr.has_method("add_storage_capacity"):
			for res in ["food", "wood", "stone", "metal", "tools", "gold"]:
				resource_mgr.add_storage_capacity(res, 500)
				
	tech_completed.emit(finished_id)
	
	# Dispatch to EventManager if available
	var em = _get_event_manager()
	if em != null:
		em.notify_tech_unlocked(finished_id, t_name)

func _get_event_manager() -> Object:
	if Engine.has_singleton("EventManager"):
		return Engine.get_singleton("EventManager")
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root.has_node("EventManager"):
		return loop.root.get_node("EventManager")
	return null

func cancel_research(resource_mgr: Object) -> Dictionary:
	if active_tech_id == "":
		return {}
		
	var def: Dictionary = TechTree.TECHNOLOGIES.get(active_tech_id, {})
	var cost: Dictionary = def.get("cost", {})
	var refund: Dictionary = {}
	
	# 50% material refund per GDD rule
	for res_id in cost:
		var ref_amt: int = int(cost[res_id] * 0.5)
		if ref_amt > 0:
			refund[res_id] = ref_amt
			if resource_mgr != null and resource_mgr.has_method("add_resource"):
				resource_mgr.call("add_resource", res_id, ref_amt)
				
	var cancelled_id := active_tech_id
	active_tech_id = ""
	active_progress_hours = 0.0
	active_required_hours = 0.0
	
	tech_cancelled.emit(cancelled_id, refund)
	return refund
