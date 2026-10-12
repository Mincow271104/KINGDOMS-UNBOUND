extends Node
## TimeManager Autoload Singleton.
## Authoritative simulation clock and calendar for KINGDOMS UNBOUND.
## Coordinates time multipliers, pause state, and hourly/daily/seasonal ticks.

signal time_speed_changed(new_speed: int)
signal hour_passed(current_hour: int, current_day: int)
signal day_passed(current_day: int, season: String, year: int)
signal season_changed(new_season: String, year: int)
signal year_passed(new_year: int)

enum Speed {
	PAUSE = 0,
	NORMAL = 1,
	FAST = 2,
	VERY_FAST = 3
}

const SEASONS: Array[String] = ["Xuân", "Hạ", "Thu", "Đông"]
const SEASON_KEYS: Array[String] = ["spring", "summer", "autumn", "winter"]
const HOURS_PER_DAY: int = 24
const DAYS_PER_SEASON: int = 10
const SEASONS_PER_YEAR: int = 4
const DAYS_PER_YEAR: int = DAYS_PER_SEASON * SEASONS_PER_YEAR # 40 days

# Current time state
var current_speed: int = Speed.NORMAL
var previous_speed: int = Speed.NORMAL
var current_hour: int = 6 # Start at 06:00 morning
var current_day: int = 1
var season_index: int = 0 # 0 = Spring
var current_year: int = 1

# Simulation accumulator (in real seconds)
# 1 real second = 1 game hour at 1x speed
var _hour_accumulator: float = 0.0

func _process(delta: float) -> void:
	if current_speed == Speed.PAUSE:
		return
		
	var multiplier: float = float(current_speed)
	_hour_accumulator += delta * multiplier
	
	# Advance full hours
	while _hour_accumulator >= 1.0:
		_hour_accumulator -= 1.0
		_advance_one_hour()

func _advance_one_hour() -> void:
	current_hour += 1
	if current_hour >= HOURS_PER_DAY:
		current_hour = 0
		_advance_one_day()
		
	hour_passed.emit(current_hour, current_day)

func _advance_one_day() -> void:
	current_day += 1
	
	# Check season transition
	var new_season_idx: int = ((current_day - 1) / DAYS_PER_SEASON) % SEASONS_PER_YEAR
	if new_season_idx != season_index:
		season_index = new_season_idx
		season_changed.emit(get_current_season_key(), current_year)
		
	# Check year transition
	var new_year: int = 1 + ((current_day - 1) / DAYS_PER_YEAR)
	if new_year != current_year:
		current_year = new_year
		year_passed.emit(current_year)
		
	day_passed.emit(current_day, get_current_season_key(), current_year)

func set_speed(speed: int) -> void:
	var clamped_speed: int = clampi(speed, Speed.PAUSE, Speed.VERY_FAST)
	if clamped_speed != current_speed:
		if current_speed != Speed.PAUSE:
			previous_speed = current_speed
		current_speed = clamped_speed
		time_speed_changed.emit(current_speed)

func pause() -> void:
	if current_speed != Speed.PAUSE:
		previous_speed = current_speed
		current_speed = Speed.PAUSE
		time_speed_changed.emit(current_speed)

func resume() -> void:
	if current_speed == Speed.PAUSE:
		current_speed = previous_speed if previous_speed != Speed.PAUSE else Speed.NORMAL
		time_speed_changed.emit(current_speed)

func toggle_pause() -> void:
	if current_speed == Speed.PAUSE:
		resume()
	else:
		pause()

func is_paused() -> bool:
	return current_speed == Speed.PAUSE

func get_current_season_name() -> String:
	return SEASONS[season_index]

func get_current_season_key() -> String:
	return SEASON_KEYS[season_index]

func get_day_in_season() -> int:
	return ((current_day - 1) % DAYS_PER_SEASON) + 1

func get_clock_string() -> String:
	return "%02d:00" % current_hour

func get_date_string() -> String:
	return "Ngày %d (%s) - Năm %d" % [get_day_in_season(), get_current_season_name(), current_year]

func get_full_time_string() -> String:
	return "%s | %s" % [get_date_string(), get_clock_string()]

func get_seasonal_farm_modifier() -> float:
	match get_current_season_key():
		"summer":
			return 1.2
		"winter":
			return 0.5
		_:
			return 1.0

func get_season_name() -> String:
	return get_current_season_key()

func get_farm_efficiency_modifier() -> float:
	return get_seasonal_farm_modifier()

## Resets time for new world generation
func reset_time(start_hour: int = 6, start_day: int = 1, start_year: int = 1) -> void:
	current_speed = Speed.NORMAL
	previous_speed = Speed.NORMAL
	current_hour = start_hour
	current_day = start_day
	season_index = ((start_day - 1) / DAYS_PER_SEASON) % SEASONS_PER_YEAR
	current_year = start_year
	_hour_accumulator = 0.0
	time_speed_changed.emit(current_speed)
