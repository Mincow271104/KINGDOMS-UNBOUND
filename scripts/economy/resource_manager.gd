extends Node
## ResourceManager Autoload Singleton.
## Authoritative Economic Ledger for KINGDOMS UNBOUND.
## Prevents double-spending, enforces storage limits, and manages atomic reservations.

signal resource_changed(id: String, available: int, total: int)
signal capacity_changed(id: String, new_capacity: int)
signal deficit_warning(id: String, message: String)

var _current_stock: Dictionary = {}
var _reserved_stock: Dictionary = {}
var _capacities: Dictionary = {}

var _daily_production_tallies: Dictionary = {}
var _daily_consumption_tallies: Dictionary = {}
var _last_day_production: Dictionary = {}
var _last_day_consumption: Dictionary = {}

var active_population: int = 24
var _is_starving: bool = false

func is_starving() -> bool:
	return _is_starving

func _ready() -> void:
	reset_economy()
	
	# Connect to TimeManager daily tick
	if Engine.has_singleton("TimeManager") or get_node_or_null("/root/TimeManager"):
		var tm = get_node("/root/TimeManager")
		tm.day_passed.connect(_on_day_passed)

func reset_economy() -> void:
	_current_stock.clear()
	_reserved_stock.clear()
	_capacities.clear()
	_daily_production_tallies.clear()
	_daily_consumption_tallies.clear()
	_is_starving = false # BUG-02: Reset starvation flag on economy reset to prevent stale state
	
	# Compute authoritative starter storage bonuses from active starter buildings (Town Hall + Storehouse)
	var starter_bonuses: Dictionary = {}
	var th_bp: Dictionary = EconomyConfig.BLUEPRINTS.get("townhall", {})
	var th_bonus: Dictionary = th_bp.get("storage_bonus", {})
	for res in th_bonus:
		starter_bonuses[res] = starter_bonuses.get(res, 0) + int(th_bonus[res])

	var sh_bp: Dictionary = EconomyConfig.BLUEPRINTS.get("storehouse", {})
	var sh_bonus: Dictionary = sh_bp.get("storage_bonus", {})
	for res in sh_bonus:
		starter_bonuses[res] = starter_bonuses.get(res, 0) + int(sh_bonus[res])

	for res_id in EconomyConfig.ALL_RESOURCES:
		var start_qty: int = EconomyConfig.STARTING_RESOURCES.get(res_id, 0)
		var base_cap: int = EconomyConfig.BASE_CAPACITIES.get(res_id, 500)
		var total_cap: int = base_cap + starter_bonuses.get(res_id, 0)
			
		_current_stock[res_id] = start_qty
		_reserved_stock[res_id] = 0
		_capacities[res_id] = total_cap
		_daily_production_tallies[res_id] = 0.0
		_daily_consumption_tallies[res_id] = 0.0
		_last_day_production[res_id] = 0.0
		_last_day_consumption[res_id] = 0.0
		
		resource_changed.emit(res_id, start_qty, start_qty)
		capacity_changed.emit(res_id, total_cap)

func get_total_stock(res_id: String) -> int:
	return _current_stock.get(res_id, 0)

func get_resource(res_id: String) -> int:
	return get_total_stock(res_id)

func get_reserved_stock(res_id: String) -> int:
	return _reserved_stock.get(res_id, 0)

func get_available_stock(res_id: String) -> int:
	var total: int = _current_stock.get(res_id, 0)
	var reserved: int = _reserved_stock.get(res_id, 0)
	return maxi(0, total - reserved)

func get_capacity(res_id: String) -> int:
	return _capacities.get(res_id, 0)

func get_storage_capacity(res_id: String) -> int:
	return get_capacity(res_id)

func has_resource(res_id: String, amount: int) -> bool:
	return get_available_stock(res_id) >= amount

func can_afford(cost: Dictionary) -> bool:
	for res_id in cost:
		var needed: int = cost[res_id]
		if get_available_stock(res_id) < needed:
			return false
	return true

## Atomically reserves all resources in cost dict (all-or-nothing).
## Prevents two systems or orders from double-spending the same available materials.
func reserve_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
		
	# All-or-nothing reservation
	for res_id in cost:
		var amount: int = cost[res_id]
		_reserved_stock[res_id] = _reserved_stock.get(res_id, 0) + amount
		resource_changed.emit(res_id, get_available_stock(res_id), get_total_stock(res_id))
	return true

## Commits a previously reserved cost (deducts from actual inventory).
func commit_cost(cost: Dictionary) -> void:
	for res_id in cost:
		var amount: int = cost[res_id]
		_reserved_stock[res_id] = maxi(0, _reserved_stock.get(res_id, 0) - amount)
		_current_stock[res_id] = maxi(0, _current_stock.get(res_id, 0) - amount)
		_daily_consumption_tallies[res_id] = _daily_consumption_tallies.get(res_id, 0.0) + float(amount)
		resource_changed.emit(res_id, get_available_stock(res_id), get_total_stock(res_id))

## Releases a previously reserved cost back to available stock.
func release_cost(cost: Dictionary) -> void:
	for res_id in cost:
		var amount: int = cost[res_id]
		_reserved_stock[res_id] = maxi(0, _reserved_stock.get(res_id, 0) - amount)
		resource_changed.emit(res_id, get_available_stock(res_id), get_total_stock(res_id))

## Adds resource to central stock, bounded by storage capacity.
## Returns amount actually stored.
func add_resource(res_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
		
	var cur: int = _current_stock.get(res_id, 0)
	var cap: int = _capacities.get(res_id, 500)
	var space: int = maxi(0, cap - cur)
	var to_add: int = mini(amount, space)
	
	if to_add > 0:
		_current_stock[res_id] = cur + to_add
		_daily_production_tallies[res_id] = _daily_production_tallies.get(res_id, 0.0) + float(to_add)
		if res_id == EconomyConfig.RES_FOOD and _current_stock[res_id] > 0:
			_is_starving = false
		resource_changed.emit(res_id, get_available_stock(res_id), get_total_stock(res_id))
		
	return to_add

## Reverses previously added resources (e.g. from an aborted or failed transaction).
## Correctly rolls back both _current_stock and _daily_production_tallies consistently,
## and restores starvation state if requested.
func rollback_added_resources(credited: Dictionary, restore_starving: Variant = null) -> void:
	for res_id in credited:
		var amt: int = int(credited[res_id])
		if amt <= 0:
			continue
		var cur: int = _current_stock.get(res_id, 0)
		_current_stock[res_id] = maxi(0, cur - amt)
		_daily_production_tallies[res_id] = maxf(0.0, _daily_production_tallies.get(res_id, 0.0) - float(amt))
		resource_changed.emit(res_id, get_available_stock(res_id), get_total_stock(res_id))
	if restore_starving != null:
		_is_starving = bool(restore_starving)

## Deducts a resource directly from stock, optionally reverting production tallies.
func deduct_resource(res_id: String, amount: int, revert_production: bool = true) -> bool:
	if amount <= 0:
		return true
	var cur: int = _current_stock.get(res_id, 0)
	if cur < amount:
		return false
	_current_stock[res_id] = cur - amount
	if revert_production:
		_daily_production_tallies[res_id] = maxf(0.0, _daily_production_tallies.get(res_id, 0.0) - float(amount))
	resource_changed.emit(res_id, get_available_stock(res_id), get_total_stock(res_id))
	return true

## Atomically adds multiple resources to central stock.
## Verifies that ALL resources can fit in remaining capacity.
## If ANY resource cannot fit, zero resources are credited and returns {"success": false, "credited": {}}.
## If all resources fit, commits all additions as a single transaction without exposing
## intermediate partial states to listeners, and returns {"success": true, "credited": credited}.
func add_resources_atomic(resources: Dictionary) -> Dictionary:
	var prev_starving: bool = _is_starving

	# Step 1: Preflight capacity check for all resources
	for res_id in resources:
		var amt: int = int(resources[res_id])
		if amt <= 0:
			continue
		var cur: int = _current_stock.get(res_id, 0)
		var cap: int = _capacities.get(res_id, 500)
		var space: int = maxi(0, cap - cur)
		if space < amt:
			return {
				"success": false,
				"reason": "Dung lượng kho không đủ cho %s (cần %d, trống %d)" % [res_id, amt, space],
				"credited": {}
			}

	# Step 2: Commit additions as one transaction without emitting intermediate signals
	var credited: Dictionary = {}
	var rollback_needed: bool = false
	var rollback_reason: String = ""

	for res_id in resources:
		var amt: int = int(resources[res_id])
		if amt <= 0:
			continue
		var cur: int = _current_stock.get(res_id, 0)
		var cap: int = _capacities.get(res_id, 500)
		var space: int = maxi(0, cap - cur)
		var to_add: int = mini(amt, space)
		if to_add < amt:
			rollback_needed = true
			rollback_reason = "Lỗi thêm tài nguyên không trọn vẹn cho %s" % res_id
			if to_add > 0:
				_current_stock[res_id] = cur + to_add
				_daily_production_tallies[res_id] = _daily_production_tallies.get(res_id, 0.0) + float(to_add)
				credited[res_id] = to_add
			break
		_current_stock[res_id] = cur + to_add
		_daily_production_tallies[res_id] = _daily_production_tallies.get(res_id, 0.0) + float(to_add)
		if res_id == EconomyConfig.RES_FOOD and _current_stock[res_id] > 0:
			_is_starving = false
		credited[res_id] = to_add

	if rollback_needed:
		rollback_added_resources(credited, prev_starving)
		return {
			"success": false,
			"reason": rollback_reason,
			"credited": {}
		}

	# Emit signals only upon full transaction success
	for res_id in credited:
		resource_changed.emit(res_id, get_available_stock(res_id), get_total_stock(res_id))

	return {"success": true, "credited": credited}

## Consumes resource immediately without prior reservation.
func consume_resource(res_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if get_available_stock(res_id) < amount:
		return false
		
	_current_stock[res_id] = _current_stock[res_id] - amount
	_daily_consumption_tallies[res_id] = _daily_consumption_tallies.get(res_id, 0.0) + float(amount)
	resource_changed.emit(res_id, get_available_stock(res_id), get_total_stock(res_id))
	return true

func add_storage_capacity(res_id: String, bonus: int) -> void:
	_capacities[res_id] = _capacities.get(res_id, 500) + bonus
	capacity_changed.emit(res_id, _capacities[res_id])

## Removes incremental storage capacity contribution upon building demolition.
## Does NOT reduce or delete existing resource inventory if capacity drops below current stock.
func remove_storage_capacity(res_id: String, bonus: int) -> void:
	if bonus <= 0:
		return
	var cur_cap: int = _capacities.get(res_id, 500)
	var new_cap: int = maxi(0, cur_cap - bonus)
	_capacities[res_id] = new_cap
	capacity_changed.emit(res_id, new_cap)

func _on_day_passed(_day: int, _season: String, _year: int) -> void:
	_execute_daily_accounting_tick()

func _execute_daily_accounting_tick() -> void:
	# Citizen Food Upkeep: 0.8 Food per citizen per day
	var food_needed: float = float(active_population) * 0.8 # 19.2 for 24 citizens
	var food_needed_int: int = int(ceil(food_needed))
	
	var current_food: int = get_available_stock(EconomyConfig.RES_FOOD)
	if current_food >= food_needed_int:
		consume_resource(EconomyConfig.RES_FOOD, food_needed_int)
		_is_starving = false
	else:
		# Partial consumption / Deficit
		consume_resource(EconomyConfig.RES_FOOD, current_food)
		_is_starving = true
		deficit_warning.emit(EconomyConfig.RES_FOOD, "Nạn đói: Kho lương thực đã cạn kiệt! Dân làng đang thiếu ăn.")

	# Rotate production/consumption tallies for daily rate display
	for res_id in EconomyConfig.ALL_RESOURCES:
		_last_day_production[res_id] = _daily_production_tallies.get(res_id, 0.0)
		_last_day_consumption[res_id] = _daily_consumption_tallies.get(res_id, 0.0)
		_daily_production_tallies[res_id] = 0.0
		_daily_consumption_tallies[res_id] = 0.0
