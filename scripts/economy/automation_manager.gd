class_name AutomationManager
extends RefCounted
## Priority Automation System for KINGDOMS UNBOUND.
## Manages rule-based priority shifts for jobs and logistics.
## Enforces a strict execution budget (MAX_RULE_CHECKS_PER_TICK) to prevent performance death spirals.

const EconomyConfig = preload("res://scripts/economy/economy_config.gd")
const JobManager = preload("res://scripts/jobs/job_manager.gd")
const WorkplaceManager = preload("res://scripts/economy/workplace_manager.gd")

const MAX_RULE_CHECKS_PER_TICK: int = 10

var food_emergency_threshold: int = 30
var winter_prep_food_threshold: int = 80
var buffer_congestion_ratio: float = 0.8

var execution_budget_used: int = 0
var total_evaluations: int = 0

## Evaluates active automation rules within execution budget.
## Returns list of actions executed.
func evaluate_rules(
	resource_mgr: Object,
	job_mgr: JobManager,
	workplace_mgr: WorkplaceManager,
	current_season: String = "spring"
) -> Array[String]:
	var actions_taken: Array[String] = []
	execution_budget_used = 0
	total_evaluations += 1
	
	if resource_mgr == null or job_mgr == null:
		return actions_taken
		
	# --- Rule 1: Food Emergency Priority Boost ---
	if execution_budget_used < MAX_RULE_CHECKS_PER_TICK:
		execution_budget_used += 1
		var food_avail: int = resource_mgr.call("get_available_stock", EconomyConfig.RES_FOOD)
		if food_avail < food_emergency_threshold:
			var farm_boosted := job_mgr.boost_jobs_priority("farmer", 2)
			var haul_boosted := job_mgr.boost_jobs_priority("hauler", 3)
			if farm_boosted > 0 or haul_boosted > 0:
				actions_taken.append(
					"Cảnh báo lương thực thấp (%d < %d): Tăng độ ưu tiên cho %d việc nông dân và %d việc vận chuyển" % [
						food_avail, food_emergency_threshold, farm_boosted, haul_boosted
					]
				)
				
	# --- Rule 2: Workplace Buffer Congestion Protection ---
	if workplace_mgr != null and execution_budget_used < MAX_RULE_CHECKS_PER_TICK:
		for wp in workplace_mgr.get_all_workplaces():
			if execution_budget_used >= MAX_RULE_CHECKS_PER_TICK:
				break
			execution_budget_used += 1
			
			if wp.buffer_capacity > 0:
				var fill_ratio: float = float(wp.buffer_amount) / float(wp.buffer_capacity)
				if fill_ratio >= buffer_congestion_ratio:
					for job in job_mgr.get_all_jobs():
						if job.type == "hauler" and job.source_workplace_id == wp.id:
							job.priority += 2
							actions_taken.append(
								"Kho tạm %s đầy (%.0f%%): Tăng ưu tiên vận chuyển hàng về kho trung tâm" % [
									wp.id, fill_ratio * 100.0
								]
							)
							break
							
	# --- Rule 3: Autumn Winter Preparation ---
	if execution_budget_used < MAX_RULE_CHECKS_PER_TICK:
		execution_budget_used += 1
		if current_season == "autumn":
			var food_avail: int = resource_mgr.call("get_available_stock", EconomyConfig.RES_FOOD)
			if food_avail < winter_prep_food_threshold:
				var boosted := job_mgr.boost_jobs_priority("farmer", 1)
				if boosted > 0:
					actions_taken.append(
						"Mùa Thu chuẩn bị Mùa Đông: Tăng sản xuất lương thực dự trữ (kho hiện tại: %d)" % food_avail
					)
					
	return actions_taken
