class_name WorkplaceManager
extends RefCounted
## Workplace & Logistics Manager for KINGDOMS UNBOUND.
## Manages production buffers, access points, and physical hauling loop.
## Prevents instant teleportation of goods from production sites to central storage.

signal buffer_changed(workplace_id: String, current_amount: int, max_capacity: int)

class WorkplaceData:
	var id: String
	var building_type: String # "farm", "woodcutter"
	var origin_cell: Vector2i
	var size: Vector2i
	var access_cell: Vector2i
	var output_resource: String
	var buffer_amount: int = 0
	var buffer_capacity: int = 50
	var base_production_per_cycle: float = 5.0
	var worker_quota: int = 5

class DropoffData:
	var id: String
	var building_type: String # "storehouse", "townhall"
	var access_cell: Vector2i

var _workplaces: Dictionary = {} # id -> WorkplaceData
var _dropoffs: Dictionary = {} # id -> DropoffData

func register_workplace(
	id: String,
	type: String,
	origin: Vector2i,
	size: Vector2i,
	access: Vector2i,
	res_id: String,
	capacity: int = 50,
	base_prod: float = 5.0,
	quota: int = 5
) -> WorkplaceData:
	var wp := WorkplaceData.new()
	wp.id = id
	wp.building_type = type
	wp.origin_cell = origin
	wp.size = size
	wp.access_cell = access
	wp.output_resource = res_id
	wp.buffer_capacity = capacity
	wp.buffer_amount = 0
	wp.base_production_per_cycle = base_prod
	wp.worker_quota = quota
	_workplaces[id] = wp
	return wp

func register_dropoff(id: String, type: String, access: Vector2i) -> DropoffData:
	var d := DropoffData.new()
	d.id = id
	d.building_type = type
	d.access_cell = access
	_dropoffs[id] = d
	return d

func get_workplace(id: String) -> WorkplaceData:
	return _workplaces.get(id, null)

func has_workplace(id: String) -> bool:
	return _workplaces.has(id)

func unregister_workplace(id: String) -> void:
	_workplaces.erase(id)

func clear_dynamic_workplaces(preserve_ids: Array = ["farm_starter", "woodcutter_starter"]) -> void:
	var to_remove: Array[String] = []
	for id in _workplaces:
		if not id in preserve_ids:
			to_remove.append(id)
	for id in to_remove:
		_workplaces.erase(id)

func get_all_workplaces() -> Array:
	return _workplaces.values()

func get_buffer_amount(workplace_id: String) -> int:
	var wp: WorkplaceData = get_workplace(workplace_id)
	return wp.buffer_amount if wp != null else 0

func get_buffer_capacity(workplace_id: String) -> int:
	var wp: WorkplaceData = get_workplace(workplace_id)
	return wp.buffer_capacity if wp != null else 0

## Deposits goods into the local workplace output buffer.
## Does NOT add to central storage; requires physical hauling.
func produce_to_buffer(workplace_id: String, season_modifier: float = 1.0) -> int:
	var wp: WorkplaceData = get_workplace(workplace_id)
	if wp == null:
		return 0
		
	var prod: float = wp.base_production_per_cycle
	if wp.output_resource == EconomyConfig.RES_FOOD:
		prod *= season_modifier
		
	var produced_qty: int = maxi(1, int(round(prod)))
	var available_space: int = maxi(0, wp.buffer_capacity - wp.buffer_amount)
	var added: int = mini(produced_qty, available_space)
	
	if added > 0:
		wp.buffer_amount += added
		buffer_changed.emit(workplace_id, wp.buffer_amount, wp.buffer_capacity)
		
	return added

## Hauler picks up goods from workplace buffer.
func pickup_from_buffer(workplace_id: String, max_amount: int) -> int:
	var wp: WorkplaceData = get_workplace(workplace_id)
	if wp == null or wp.buffer_amount <= 0:
		return 0
		
	var taken: int = mini(max_amount, wp.buffer_amount)
	wp.buffer_amount -= taken
	buffer_changed.emit(workplace_id, wp.buffer_amount, wp.buffer_capacity)
	return taken

## Finds nearest registered dropoff access cell.
func get_nearest_dropoff_cell(from_cell: Vector2i) -> Vector2i:
	if _dropoffs.is_empty():
		return Vector2i(32, 32) # Fallback to plaza
		
	var best_dist := 999999
	var best_cell: Vector2i = Vector2i(32, 32)
	
	for d in _dropoffs.values():
		var dist := IsoMath.grid_distance(from_cell, d.access_cell)
		if dist < best_dist:
			best_dist = dist
			best_cell = d.access_cell
			
	return best_cell

## Checks all workplace buffers and creates hauling jobs when items are awaiting transport.
func update_hauling_jobs(job_mgr: JobManager) -> int:
	var created_count := 0
	
	for wp in _workplaces.values():
		if wp.buffer_amount >= 5: # Threshold to dispatch a hauler
			# Check if there is already an available or reserved hauling job for this workplace
			if not _has_pending_hauling_job(job_mgr, wp.id):
				var dropoff := get_nearest_dropoff_cell(wp.access_cell)
				var haul_amount := mini(10, wp.buffer_amount)
				var job = job_mgr.create_hauling_job(
					wp.id,
					wp.access_cell,
					dropoff,
					wp.output_resource,
					haul_amount,
					"Vận chuyển %d %s từ %s về kho" % [haul_amount, wp.output_resource, wp.id]
				)
				if job != null:
					created_count += 1
					
	return created_count

func _has_pending_hauling_job(job_mgr: JobManager, workplace_id: String) -> bool:
	for job in job_mgr.get_all_jobs():
		if job.type == "hauler" and job.source_workplace_id == workplace_id:
			if job.state == JobManager.JobState.AVAILABLE or job.state == JobManager.JobState.RESERVED or job.state == JobManager.JobState.IN_PROGRESS:
				return true
	return false
