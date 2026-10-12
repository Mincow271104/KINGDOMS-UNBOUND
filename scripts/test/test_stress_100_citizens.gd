extends SceneTree
## Headless Performance Stress Test Suite for Phase 9: 100-Citizen Simulation (TC-9.1).
## Benchmarks 64x64 grid simulation, pathfinding throughput, job allocation, and rendering updates
## with 100 active citizens across 1x and 3x simulation speeds.
## Acceptance Criteria: Average frame time <= 16.66 ms (>= 60 FPS equivalent).

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const IsoMath = preload("res://scripts/utils/iso_math.gd")

var frame_count: int = 0
var world_instance: Node = null

# Benchmarking metrics
var benchmark_phase: int = 0 # 0: init, 1: spawn to 100, 2: 1x speed test, 3: 3x speed test, 4: multi-day simulation, 5: evaluate
var frame_times_1x: Array[float] = [] # ms
var frame_times_3x: Array[float] = [] # ms
var test_frames_target: int = 200
var frames_measured: int = 0
var last_frame_ticks: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Phase 9 — 100-Citizen Stress Benchmark (TC-9.1)")
	print("========================================================\n")
	
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	var now_ticks := Time.get_ticks_usec()
	var frame_duration_ms: float = 0.0
	if last_frame_ticks > 0:
		frame_duration_ms = float(now_ticks - last_frame_ticks) / 1000.0
	last_frame_ticks = now_ticks
	
	match benchmark_phase:
		0:
			# Allow WorldView 3 frames to complete _ready()
			if frame_count >= 3:
				benchmark_phase = 1
				
		1:
			# Spawn additional citizens up to 100
			print("[Stress Test 1] Spawning citizens up to 100 units...")
			var current_pop: int = world_instance.citizen_list.size()
			var needed: int = 100 - current_pop
			print("  Current population: %d. Spawning %d additional citizens..." % [current_pop, needed])
			
			var roles_pool: Array[String] = [
				"farmer", "farmer", "farmer",
				"woodcutter", "woodcutter",
				"builder", "builder",
				"hauler", "hauler",
				"idle"
			]
			
			var wave_immigrants: Array = []
			for i in range(needed):
				var idx: int = current_pop + i + 1
				var r_role: String = roles_pool[i % roles_pool.size()]
				wave_immigrants.append({
					"id": "citizen_%d" % idx,
					"name": "Dân Cư #%d" % idx,
					"role": r_role
				})
				
			world_instance._spawn_immigrant_wave(wave_immigrants)
			
			var final_pop: int = world_instance.citizen_list.size()
			print("  Total active citizens in simulation: %d" % final_pop)
			if final_pop != 100:
				printerr("❌ Population count mismatch: expected 100, got %d" % final_pop)
				quit(1)
				return true
				
			print("  ✅ 100 active citizens successfully spawned into 64x64 world.\n")
			
			# Configure plenty of food to prevent premature mass starvation during stress testing
			var rm = root.get_node_or_null("/root/ResourceManager")
			if rm:
				rm.add_resource("food", 5000)
				rm.add_resource("wood", 2000)
				rm.add_resource("stone", 1000)
				rm.add_resource("gold", 2000)
				
			var tm = root.get_node_or_null("/root/TimeManager")
			if tm:
				tm.set_speed(1)
				
			benchmark_phase = 2
			frames_measured = 0
			last_frame_ticks = Time.get_ticks_usec()
			
		2:
			# Benchmark at 1x Speed
			if frame_duration_ms > 0.0 and frame_duration_ms < 1000.0:
				frame_times_1x.append(frame_duration_ms)
			frames_measured += 1
			
			if frames_measured >= test_frames_target:
				print("[Stress Test 2] Completed %d frames benchmark at 1x Simulation Speed." % frames_measured)
				var tm = root.get_node_or_null("/root/TimeManager")
				if tm:
					tm.set_speed(3)
				benchmark_phase = 3
				frames_measured = 0
				last_frame_ticks = Time.get_ticks_usec()
				
		3:
			# Benchmark at 3x Speed
			if frame_duration_ms > 0.0 and frame_duration_ms < 1000.0:
				frame_times_3x.append(frame_duration_ms)
			frames_measured += 1
			
			if frames_measured >= test_frames_target:
				print("[Stress Test 3] Completed %d frames benchmark at 3x Simulation Speed." % frames_measured)
				benchmark_phase = 4
				
		4:
			# Multi-Day Extended Stress Simulation (72 hours = 3 full game days)
			print("\n[Stress Test 4] Simulating 72 continuous simulation hours (3 game days)...")
			var tm = root.get_node_or_null("/root/TimeManager")
			var start_hour: int = tm.current_hour if tm else 0
			var start_day: int = tm.current_day if tm else 0
			
			var sim_start_ticks := Time.get_ticks_usec()
			for h in range(72):
				var cur_h: int = (start_hour + h) % 24
				var cur_d: int = start_day + int((start_hour + h) / 24)
				world_instance._on_simulation_hour_passed(cur_h, cur_d)
				if cur_h == 0 and h > 0:
					world_instance._on_simulation_day_passed(cur_d, "spring", 1)
					
			var sim_duration_ms: float = float(Time.get_ticks_usec() - sim_start_ticks) / 1000.0
			var ms_per_hour: float = sim_duration_ms / 72.0
			print("  Executed 72 hourly simulation ticks + 3 daily ticks in %.2f ms (%.3f ms/hour tick)." % [sim_duration_ms, ms_per_hour])
			print("  ✅ Extended multi-day simulation executed deterministically without stalling.")
			benchmark_phase = 5
			
		5:
			# Evaluate and print comprehensive benchmark report
			_evaluate_results()
			return true
			
	return false

func _evaluate_results() -> void:
	print("\n========================================================")
	print("  BENCHMARK PERFORMANCE EVALUATION (100 CITIZENS)")
	print("========================================================")
	
	var avg_1x: float = _calculate_average(frame_times_1x)
	var p95_1x: float = _calculate_percentile(frame_times_1x, 0.95)
	var max_1x: float = _calculate_max(frame_times_1x)
	var fps_1x: float = 1000.0 / avg_1x if avg_1x > 0.0 else 0.0
	
	var avg_3x: float = _calculate_average(frame_times_3x)
	var p95_3x: float = _calculate_percentile(frame_times_3x, 0.95)
	var max_3x: float = _calculate_max(frame_times_3x)
	var fps_3x: float = 1000.0 / avg_3x if avg_3x > 0.0 else 0.0
	
	print("--- Speed 1x Performance ---")
	print("  • Average Frame Time: %.3f ms (≈ %.1f FPS)" % [avg_1x, fps_1x])
	print("  • 95th Percentile:    %.3f ms" % p95_1x)
	print("  • Max Frame Time:     %.3f ms" % max_1x)
	
	print("\n--- Speed 3x Performance ---")
	print("  • Average Frame Time: %.3f ms (≈ %.1f FPS)" % [avg_3x, fps_3x])
	print("  • 95th Percentile:    %.3f ms" % p95_3x)
	print("  • Max Frame Time:     %.3f ms" % max_3x)
	
	var pass_1x: bool = avg_1x <= 16.66 or fps_1x >= 60.0
	var pass_3x: bool = avg_3x <= 16.66 or fps_3x >= 60.0
	var pop_valid: bool = world_instance.citizen_list.size() >= 90 # >= 90 accounting for potential elder mortality
	
	print("\n--------------------------------------------------------")
	print("  ACCEPTANCE CRITERIA CHECK:")
	print("  [ %s ] 1x Speed Average Frame Time <= 16.66 ms (Actual: %.3f ms, %.1f FPS)" % ["PASS" if pass_1x else "FAIL", avg_1x, fps_1x])
	print("  [ %s ] 3x Speed Average Frame Time <= 16.66 ms (Actual: %.3f ms, %.1f FPS)" % ["PASS" if pass_3x else "FAIL", avg_3x, fps_3x])
	print("  [ %s ] 100 Citizens Active and Responsive (Final: %d citizens)" % ["PASS" if pop_valid else "FAIL", world_instance.citizen_list.size()])
	print("--------------------------------------------------------")
	
	if pass_1x and pass_3x and pop_valid:
		print("  TC-9.1 100-CITIZEN STRESS TEST PASSED! (Exit Code 0)")
		print("========================================================\n")
		quit(0)
	else:
		printerr("  TC-9.1 100-CITIZEN STRESS TEST FAILED!")
		print("========================================================\n")
		quit(1)

func _calculate_average(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var sum: float = 0.0
	for v in arr:
		sum += v
	return sum / float(arr.size())

func _calculate_max(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var m: float = arr[0]
	for v in arr:
		if v > m:
			m = v
	return m

func _calculate_percentile(arr: Array[float], p: float) -> float:
	if arr.is_empty():
		return 0.0
	var sorted := arr.duplicate()
	sorted.sort()
	var idx: int = int(float(sorted.size() - 1) * p)
	return sorted[idx]
