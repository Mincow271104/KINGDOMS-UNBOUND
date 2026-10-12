extends SceneTree

const TimeManagerScript = preload("res://scripts/core/time_manager.gd")

func _init() -> void:
	print("--- Running TestTimeManager (TC-1.4) ---")
	var failures: int = 0
	
	var tm: Node = TimeManagerScript.new()
	root.add_child(tm)
	
	# Initial conditions
	tm.reset_time(6, 1, 1)
	if tm.current_hour != 6 or tm.current_day != 1 or tm.current_year != 1:
		printerr("FAIL: reset_time did not set initial hour/day/year correctly")
		failures += 1
	else:
		print("PASS: initial time correctly set to Day 1 06:00")
		
	# Test pause prevents time progression
	tm.pause()
	if not tm.is_paused():
		printerr("FAIL: is_paused() returned false after pause()")
		failures += 1
	tm._process(10.0) # Simulate 10 seconds passing
	if tm.current_hour != 6:
		printerr("FAIL: time progressed while paused!")
		failures += 1
	else:
		print("PASS: pause strictly halts time progression")
		
	# Test normal speed 1x
	tm.resume()
	tm._process(1.0) # 1 real second = 1 game hour
	if tm.current_hour != 7:
		printerr("FAIL: expected hour 7, got %d" % tm.current_hour)
		failures += 1
	else:
		print("PASS: 1.0s at 1x speed advances exactly 1 hour (06:00 -> 07:00)")
		
	# Test day progression: advance 17 hours to 24:00 (midnight = next day)
	tm._process(17.0)
	if tm.current_hour != 0 or tm.current_day != 2:
		printerr("FAIL: expected midnight Day 2, got Day %d %02d:00" % [tm.current_day, tm.current_hour])
		failures += 1
	else:
		print("PASS: 24-hour cycle advances to Day 2 at 00:00")
		
	# Test seasonal modifier
	if tm.get_seasonal_farm_modifier() != 1.0:
		printerr("FAIL: expected spring farm modifier 1.0, got %f" % tm.get_seasonal_farm_modifier())
		failures += 1
	else:
		print("PASS: Spring farm modifier = 1.0")
		
	# Test advance to Winter (Day 31)
	tm.reset_time(0, 31, 1)
	if tm.get_current_season_key() != "winter":
		printerr("FAIL: expected winter on day 31, got %s" % tm.get_current_season_key())
		failures += 1
	elif tm.get_seasonal_farm_modifier() != 0.5:
		printerr("FAIL: expected winter farm modifier 0.5, got %f" % tm.get_seasonal_farm_modifier())
		failures += 1
	else:
		print("PASS: Winter on Day 31 correctly applies 0.5x farm modifier")

	tm.queue_free()

	if failures == 0:
		print("=== TC-1.4 ALL TIME MANAGER TESTS PASSED ===")
		quit(0)
	else:
		printerr("=== TC-1.4 FAILED WITH %d FAILURES ===" % failures)
		quit(1)
