extends SceneTree
## Deterministic Verification Suite for WorldEventSystem & Gameplay Effect Integrity (Batch 3B / BUG-04).
## Verifies all 5 events and 6 effect keys:
## - bountiful_harvest: bonus_food (+30 once) & farm_modifier_bonus (+50% farm output for 2 days, expires on day D+2)
## - heatwave: fatigue_multiplier (1.25x hourly fatigue gain for 2 days, expires on day D+2)
## - wandering_herbalist: grant_resource (herbs +20) & heal_citizens (+15.0 health for alive citizens, clamped to [0, 100])
## - bandit_scouts: morale_penalty (-8.0 morale for alive citizens, clamped to [0, 100])
## - merchant_tribute: grant_resource (gold +50)
## Also verifies dead/dying citizen immunity, non-revival, and idempotency against double application.

const WorldEventSystemScript = preload("res://scripts/core/world_event_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const ResourceManagerScript = preload("res://scripts/economy/resource_manager.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + msg)
	else:
		_failed += 1
		printerr("  [FAIL] " + msg)

class MockEventManager extends RefCounted:
	var triggered_events: Array[Dictionary] = []
	func trigger_event(event_id: String, title: String, desc: String, is_positive: bool, payload: Dictionary = {}) -> void:
		triggered_events.append({
			"id": event_id,
			"title": title,
			"description": desc,
			"is_positive": is_positive,
			"payload": payload
		})

func _init() -> void:
	print("=== Running TestWorldEvents (Batch 3B: BUG-04 World Event Effect Integrity) ===")

	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var world_data = WorldGeneratorScript.generate(12345)
	var nav = GridNavigationScript.new(world_data)
	var job_mgr = JobManagerScript.new()
	var wp_mgr = WorkplaceManagerScript.new()
	wp_mgr.register_workplace("farm_starter", "farm", Vector2i(36, 35), Vector2i(2, 2), Vector2i(35, 35), EconomyConfigScript.RES_FOOD, 50, 5.0, 5)

	# -------------------------------------------------------------------------
	# Test 1: BUG-04A — Audit all EVENTS and verify every effect key is recognized
	# -------------------------------------------------------------------------
	print("\n--- Test 1: Event Effect Key Audit (BUG-04A) ---")
	var supported_keys := {
		"farm_modifier_bonus": true,
		"bonus_food": true,
		"fatigue_multiplier": true,
		"grant_resource": true,
		"heal_citizens": true,
		"morale_penalty": true
	}
	_assert(WorldEventSystemScript.EVENTS.size() == 5, "EVENTS table defines all 5 canonical world events")
	for ev_def in WorldEventSystemScript.EVENTS:
		var ev_id: String = str(ev_def.get("id", ""))
		var eff: Dictionary = ev_def.get("effect", {})
		_assert(not eff.is_empty(), "Event '%s' has non-empty effect dictionary" % ev_id)
		for k in eff.keys():
			_assert(supported_keys.has(str(k)), "Event '%s' effect key '%s' has a registered runtime consumer" % [ev_id, str(k)])

	# -------------------------------------------------------------------------
	# Test 2 & 3: BUG-04B — bountiful_harvest (bonus_food +30 once, +50% farm output for 2 days, expires cleanly)
	# -------------------------------------------------------------------------
	print("\n--- Test 2 & 3: bountiful_harvest Farm Modifier & Expiration (BUG-04B) ---")
	var es = WorldEventSystemScript.new(12345)
	var em = MockEventManager.new()
	rm.reset_economy()

	var farmer = CitizenControllerScript.new()
	farmer.init_citizen("cit_farmer_1", "Nông Dân A", "farmer", Vector2i(35, 35), nav, job_mgr, wp_mgr)
	farmer.set_event_system(es)
	root.add_child(farmer)

	# Baseline farm production before event (Day 5, Spring modifier 1.0 -> base 5.0 -> 5 food in buffer)
	var farm_wp = wp_mgr.get_workplace("farm_starter")
	farm_wp.buffer_amount = 0
	var job_base = job_mgr.create_job("farmer", Vector2i(35, 35), "Thu hoạch lúa", "farm_starter", 1.0, 1, true)
	job_base.state = JobManagerScript.JobState.IN_PROGRESS
	job_base.work_hours_done = 0.0
	farmer.active_job = job_base
	farmer.current_state = CitizenControllerScript.State.WORKING
	farmer._process_working(1.0)
	_assert(farm_wp.buffer_amount == 5, "Baseline farm production before bountiful_harvest produces 5 food (got %d)" % farm_wp.buffer_amount)

	# Trigger bountiful_harvest on Day 5
	var food_before: int = rm.get_available_stock(EconomyConfigScript.RES_FOOD)
	var bh_ev: Dictionary = es.trigger_event_by_id("bountiful_harvest", 5, rm, em, [farmer])
	var food_after: int = rm.get_available_stock(EconomyConfigScript.RES_FOOD)
	_assert(not bh_ev.is_empty() and bh_ev.get("id") == "bountiful_harvest", "bountiful_harvest triggered on Day 5")
	_assert(food_after == food_before + 30, "bountiful_harvest granted +30 bonus_food immediately (before=%d, after=%d)" % [food_before, food_after])
	_assert(is_equal_approx(es.get_active_farm_modifier_bonus(5), 0.5), "Active farm modifier bonus on Day 5 is +0.5")
	_assert(is_equal_approx(es.get_farm_production_multiplier(1.0, 5), 1.5), "Farm production multiplier on Day 5 is 1.5x")

	# Farm production during Day 5 (first active day): 5.0 * 1.5 = 7.5 -> round(7.5) = 8 food
	farm_wp.buffer_amount = 0
	farmer.active_job = job_base
	job_base.state = JobManagerScript.JobState.IN_PROGRESS
	job_base.work_hours_done = 0.0
	farmer.current_state = CitizenControllerScript.State.WORKING
	farmer._process_working(1.0)
	_assert(farm_wp.buffer_amount == 8, "Farm production during bountiful_harvest Day 5 is 8 food (+50%% over 5, got %d)" % farm_wp.buffer_amount)

	# Day 6 (second active day): still active
	es.update_daily_modifiers(6)
	_assert(is_equal_approx(es.get_active_farm_modifier_bonus(6), 0.5), "Active farm modifier bonus remains +0.5 on Day 6 (day 2 of 2)")
	farm_wp.buffer_amount = 0
	farmer.active_job = job_base
	job_base.state = JobManagerScript.JobState.IN_PROGRESS
	job_base.work_hours_done = 0.0
	farmer.current_state = CitizenControllerScript.State.WORKING
	farmer._process_working(1.0)
	_assert(farm_wp.buffer_amount == 8, "Farm production during bountiful_harvest Day 6 is still 8 food (got %d)" % farm_wp.buffer_amount)

	# Re-triggering bountiful_harvest on Day 6 must refresh duration, NOT stack to +1.0 (2.0x)
	es.trigger_event_by_id("bountiful_harvest", 6, rm, em, [farmer])
	_assert(is_equal_approx(es.get_active_farm_modifier_bonus(6), 0.5), "Re-triggering bountiful_harvest does not stack farm bonus above 0.5")

	# Seasonal interaction during bountiful_harvest: Summer (1.2) * 1.5 = 1.8 -> 5.0 * 1.8 = 9 food; Winter (0.5) * 1.5 = 0.75 -> round(5.0 * 0.75) = 4 food
	_assert(is_equal_approx(es.get_farm_production_multiplier(1.2, 6), 1.8), "Summer (1.2x) + bountiful_harvest (+50%%) yields 1.8x farm multiplier")
	_assert(is_equal_approx(es.get_farm_production_multiplier(0.5, 6), 0.75), "Winter (0.5x) + bountiful_harvest (+50%%) yields 0.75x farm multiplier")

	# Day 8 (after 2-day duration from Day 6 trigger expires): bonus must be 0.0 and production back to 5
	es.update_daily_modifiers(8)
	_assert(is_equal_approx(es.get_active_farm_modifier_bonus(8), 0.0), "Farm modifier bonus expires to 0.0 on Day 8 after 2-day duration")
	_assert(not es.is_farm_bonus_active(8), "is_farm_bonus_active(8) returns false after expiration")
	farm_wp.buffer_amount = 0
	farmer.active_job = job_base
	job_base.state = JobManagerScript.JobState.IN_PROGRESS
	job_base.work_hours_done = 0.0
	farmer.current_state = CitizenControllerScript.State.WORKING
	farmer._process_working(1.0)
	_assert(farm_wp.buffer_amount == 5, "Farm production after bountiful_harvest expiration returns to baseline 5 food (got %d)" % farm_wp.buffer_amount)

	# -------------------------------------------------------------------------
	# Test 4 & 5: BUG-04C — heatwave (fatigue_multiplier 1.25x while active, reverts to 1.0x after expiration)
	# -------------------------------------------------------------------------
	print("\n--- Test 4 & 5: heatwave Fatigue Multiplier & Expiration (BUG-04C) ---")
	rm.reset_economy() # Ensure plenty of food so starvation fatigue is not active
	farmer.hunger = 10.0
	farmer.fatigue = 10.0
	farmer.current_state = CitizenControllerScript.State.WORKING

	# Baseline hourly fatigue gain in WORKING state on Day 10 (no heatwave): +4.0
	farmer._on_hour_passed(8, 10)
	_assert(is_equal_approx(farmer.fatigue, 14.0), "Baseline working fatigue gain is +4.0/hr (10.0 -> %.2f)" % farmer.fatigue)

	# Trigger heatwave on Day 10
	var hw_ev: Dictionary = es.trigger_event_by_id("heatwave", 10, rm, em, [farmer])
	_assert(not hw_ev.is_empty() and hw_ev.get("id") == "heatwave", "heatwave triggered on Day 10")
	_assert(is_equal_approx(es.get_active_fatigue_multiplier(10), 1.25), "Active fatigue multiplier on Day 10 is 1.25")
	_assert(es.is_heatwave_active(10), "is_heatwave_active(10) is true")

	# Working fatigue gain during heatwave on Day 10: +4.0 * 1.25 = +5.0
	farmer.fatigue = 10.0
	farmer._on_hour_passed(9, 10)
	_assert(is_equal_approx(farmer.fatigue, 15.0), "Heatwave working fatigue gain is +5.0/hr (4.0 * 1.25, got %.2f)" % farmer.fatigue)

	# Idle fatigue gain during heatwave on Day 11 (day 2 of 2): +1.0 * 1.25 = +1.25
	farmer.current_state = CitizenControllerScript.State.IDLE
	farmer.fatigue = 20.0
	farmer._on_hour_passed(9, 11)
	_assert(is_equal_approx(farmer.fatigue, 21.25), "Heatwave idle fatigue gain on Day 11 is +1.25/hr (1.0 * 1.25, got %.2f)" % farmer.fatigue)

	# Re-triggering heatwave on Day 11 refreshes duration, does NOT stack to 1.25 * 1.25
	es.trigger_event_by_id("heatwave", 11, rm, em, [farmer])
	_assert(is_equal_approx(es.get_active_fatigue_multiplier(11), 1.25), "Re-triggering heatwave does not stack multiplier above 1.25")

	# Day 13 (after 2-day duration from Day 11 expires): fatigue multiplier reverts to 1.0
	es.update_daily_modifiers(13)
	_assert(is_equal_approx(es.get_active_fatigue_multiplier(13), 1.0), "Fatigue multiplier reverts to 1.0 on Day 13 after expiration")
	_assert(not es.is_heatwave_active(13), "is_heatwave_active(13) is false after expiration")
	farmer.current_state = CitizenControllerScript.State.WORKING
	farmer.fatigue = 10.0
	farmer._on_hour_passed(10, 13)
	_assert(is_equal_approx(farmer.fatigue, 14.0), "Post-heatwave working fatigue gain reverts to baseline +4.0/hr (got %.2f)" % farmer.fatigue)

	# -------------------------------------------------------------------------
	# Test 6 & 7: wandering_herbalist & Dead/Dying Citizen Protection (BUG-04D)
	# -------------------------------------------------------------------------
	print("\n--- Test 6 & 7: wandering_herbalist Resource Grant, Healing & Dead Citizen Immunity (BUG-04D) ---")
	rm.reset_economy()
	var herbs_before: int = rm.get_available_stock(EconomyConfigScript.RES_HERBS)

	var cit_injured = CitizenControllerScript.new()
	cit_injured.init_citizen("cit_injured", "Dân Bị Thương", "idle", Vector2i(32, 32), nav, job_mgr, wp_mgr)
	cit_injured.health = 60.0
	root.add_child(cit_injured)

	var cit_nearly_full = CitizenControllerScript.new()
	cit_nearly_full.init_citizen("cit_nearly_full", "Dân Khỏe Mạnh", "idle", Vector2i(32, 32), nav, job_mgr, wp_mgr)
	cit_nearly_full.health = 92.0
	root.add_child(cit_nearly_full)

	var cit_dead_flag = CitizenControllerScript.new()
	cit_dead_flag.init_citizen("cit_dead_flag", "Dân Đã Mất", "idle", Vector2i(32, 32), nav, job_mgr, wp_mgr)
	cit_dead_flag.die("Tử trận")
	root.add_child(cit_dead_flag)

	var cit_zero_hp = CitizenControllerScript.new()
	cit_zero_hp.init_citizen("cit_zero_hp", "Dân Hấp Hối", "idle", Vector2i(32, 32), nav, job_mgr, wp_mgr)
	cit_zero_hp.health = 0.0
	root.add_child(cit_zero_hp)

	var test_citizens := [cit_injured, cit_nearly_full, cit_dead_flag, cit_zero_hp]
	var wh_ev: Dictionary = es.trigger_event_by_id("wandering_herbalist", 15, rm, em, test_citizens)
	var herbs_after: int = rm.get_available_stock(EconomyConfigScript.RES_HERBS)

	_assert(herbs_after == herbs_before + 20, "wandering_herbalist granted +20 herbs (before=%d, after=%d)" % [herbs_before, herbs_after])
	_assert(is_equal_approx(cit_injured.health, 75.0), "Injured alive citizen healed +15.0 (60.0 -> %.1f)" % cit_injured.health)
	_assert(is_equal_approx(cit_nearly_full.health, 100.0), "Nearly full citizen health clamped at 100.0 (92.0 + 15.0 -> %.1f)" % cit_nearly_full.health)
	_assert(is_equal_approx(cit_dead_flag.health, 0.0) and not cit_dead_flag.is_alive(), "Dead citizen (_death_processed=true) was NOT revived by heal_citizens (health=%.1f)" % cit_dead_flag.health)
	_assert(is_equal_approx(cit_zero_hp.health, 0.0) and not cit_zero_hp.is_alive(), "Zero-HP citizen (health=0.0) was NOT revived by heal_citizens (health=%.1f)" % cit_zero_hp.health)

	# -------------------------------------------------------------------------
	# Test 8: bandit_scouts Morale Penalty, Clamping & Dead Citizen Immunity (BUG-04D)
	# -------------------------------------------------------------------------
	print("\n--- Test 8: bandit_scouts Morale Penalty & Clamping (BUG-04D) ---")
	cit_injured.morale = 50.0
	cit_nearly_full.morale = 5.0
	cit_dead_flag.morale = 40.0
	cit_zero_hp.morale = 35.0

	var bs_ev: Dictionary = es.trigger_event_by_id("bandit_scouts", 20, rm, em, test_citizens)
	_assert(not bs_ev.is_empty() and bs_ev.get("id") == "bandit_scouts", "bandit_scouts triggered on Day 20")
	_assert(is_equal_approx(cit_injured.morale, 42.0), "Alive citizen morale reduced by 8.0 (50.0 -> %.1f)" % cit_injured.morale)
	_assert(is_equal_approx(cit_nearly_full.morale, 0.0), "Low-morale citizen clamped to 0.0 (5.0 - 8.0 -> %.1f)" % cit_nearly_full.morale)
	_assert(is_equal_approx(cit_dead_flag.morale, 40.0), "Dead citizen morale untouched by bandit_scouts (remained %.1f)" % cit_dead_flag.morale)
	_assert(is_equal_approx(cit_zero_hp.morale, 35.0), "Zero-HP citizen morale untouched by bandit_scouts (remained %.1f)" % cit_zero_hp.morale)

	# -------------------------------------------------------------------------
	# Test 9: merchant_tribute Gold Grant
	# -------------------------------------------------------------------------
	print("\n--- Test 9: merchant_tribute Resource Grant ---")
	var gold_before: int = rm.get_available_stock(EconomyConfigScript.RES_GOLD)
	var mt_ev: Dictionary = es.trigger_event_by_id("merchant_tribute", 25, rm, em, test_citizens)
	var gold_after: int = rm.get_available_stock(EconomyConfigScript.RES_GOLD)
	_assert(not mt_ev.is_empty() and mt_ev.get("id") == "merchant_tribute", "merchant_tribute triggered on Day 25")
	_assert(gold_after == gold_before + 50, "merchant_tribute granted +50 gold (before=%d, after=%d)" % [gold_before, gold_after])

	# -------------------------------------------------------------------------
	# Test 10: Cooldown enforcement (min_days_between_events = 4)
	# -------------------------------------------------------------------------
	print("\n--- Test 10: Cooldown Enforcement (min_days_between_events) ---")
	es.last_event_day = 30
	var cd_ev_1: Dictionary = es.check_and_trigger_event(31, rm, em, test_citizens)
	var cd_ev_2: Dictionary = es.check_and_trigger_event(33, rm, em, test_citizens)
	_assert(cd_ev_1.is_empty() and cd_ev_2.is_empty(), "check_and_trigger_event respects min_days_between_events=4 cooldown on Days 31..33")
	var cd_ev_3: Dictionary = es.check_and_trigger_event(34, rm, em, test_citizens)
	_assert(not cd_ev_3.is_empty() and es.last_event_day == 34, "check_and_trigger_event triggers once cooldown elapsed on Day 34")

	# -------------------------------------------------------------------------
	# Test 11: Idempotency — No Double Application of Resource or Citizen Effects
	# -------------------------------------------------------------------------
	print("\n--- Test 11: Idempotency Against Double Application ---")
	rm.reset_economy()
	cit_injured.health = 50.0
	cit_injured.morale = 50.0
	var herbs_start: int = rm.get_available_stock(EconomyConfigScript.RES_HERBS)

	# Simulate WorldView calling check_and_trigger_event(..., citizen_list) AND then apply_citizen_effects(ev_result, citizen_list)
	# Also include duplicate reference [cit_injured, cit_injured] in array to verify per-instance deduplication
	var dup_list := [cit_injured, cit_injured]
	var idemp_ev: Dictionary = es.trigger_event_by_id("wandering_herbalist", 40, rm, em, dup_list)
	var second_apply_count: int = es.apply_citizen_effects(idemp_ev, dup_list)
	es._apply_resource_effects(idemp_ev, rm)

	_assert(rm.get_available_stock(EconomyConfigScript.RES_HERBS) == herbs_start + 20, "Resource grant applied once even if _apply_resource_effects is called again")
	_assert(is_equal_approx(cit_injured.health, 65.0), "Citizen heal applied once (+15.0 -> 65.0) despite duplicate list entries and second apply_citizen_effects call (got %.1f)" % cit_injured.health)
	_assert(second_apply_count == 0, "Second apply_citizen_effects call on same event instance returns 0")

	# -------------------------------------------------------------------------
	# Test 12: Heatwave Callback on Dead, 0-HP, and Queued-For-Deletion Citizens
	# -------------------------------------------------------------------------
	print("\n--- Test 12: Heatwave Callback Safety on Dead / 0-HP / Queued-For-Deletion Citizens ---")
	es.trigger_event_by_id("heatwave", 45, rm, em, [cit_injured])
	cit_dead_flag.fatigue = 30.0
	cit_dead_flag._on_hour_passed(12, 45)
	_assert(is_equal_approx(cit_dead_flag.fatigue, 30.0), "Dead citizen (_death_processed=true) ignores _on_hour_passed during heatwave (fatigue remained %.1f)" % cit_dead_flag.fatigue)

	cit_zero_hp.fatigue = 25.0
	cit_zero_hp._on_hour_passed(12, 45)
	_assert(is_equal_approx(cit_zero_hp.fatigue, 25.0), "Zero-HP citizen (health=0.0) ignores _on_hour_passed during heatwave (fatigue remained %.1f)" % cit_zero_hp.fatigue)

	var cit_queued = CitizenControllerScript.new()
	cit_queued.init_citizen("cit_queued", "Dân Sắp Xóa", "idle", Vector2i(32, 32), nav, job_mgr, wp_mgr)
	cit_queued.health = 70.0
	cit_queued.morale = 70.0
	root.add_child(cit_queued)
	cit_queued.queue_free()
	_assert(cit_queued.is_queued_for_deletion(), "cit_queued is marked is_queued_for_deletion()")
	var queued_ev: Dictionary = es.get_event_definition("wandering_herbalist")
	var queued_affected: int = es.apply_citizen_effects(queued_ev, [cit_queued, null])
	_assert(queued_affected == 0 and is_equal_approx(cit_queued.health, 70.0), "Queued-for-deletion and null citizen entries are safely skipped by apply_citizen_effects")

	# -------------------------------------------------------------------------
	# Test 13: WorldEventSystem Serialization, Deserialization, Legacy Reset & RNG Continuation
	# -------------------------------------------------------------------------
	print("\n--- Test 13: WorldEventSystem Serialization, Deserialization & RNG Stream Continuation ---")
	var es_persist = WorldEventSystemScript.new(77777)
	es_persist.trigger_event_by_id("bountiful_harvest", 10, rm, em, [])
	es_persist.trigger_event_by_id("heatwave", 11, rm, em, [])
	var snap: Dictionary = es_persist.serialize()

	_assert(int(snap.get("last_event_day", -1)) == 11, "Serialized last_event_day == 11")
	_assert(is_equal_approx(float(snap.get("active_farm_modifier_bonus", 0.0)), 0.5), "Serialized active_farm_modifier_bonus == 0.5")
	_assert(int(snap.get("farm_bonus_expires_day", -1)) == 12, "Serialized farm_bonus_expires_day == 12")
	_assert(is_equal_approx(float(snap.get("active_fatigue_multiplier", 1.0)), 1.25), "Serialized active_fatigue_multiplier == 1.25")
	_assert(int(snap.get("fatigue_mult_expires_day", -1)) == 13, "Serialized fatigue_mult_expires_day == 13")
	_assert(String(snap.get("rng_state", "")).is_valid_int(), "Serialized rng_state is a valid integer string")

	# Compute reference next event on Day 15 from es_persist
	var ref_next_ev: Dictionary = es_persist.check_and_trigger_event(15, null, null, [])

	# Restore into a fresh instance on Day 11 (both modifiers still active)
	var es_restored = WorldEventSystemScript.new(11111)
	es_restored.deserialize(snap, 11)
	_assert(is_equal_approx(es_restored.get_active_farm_modifier_bonus(11), 0.5), "Restored farm bonus is 0.5 on Day 11")
	_assert(is_equal_approx(es_restored.get_active_fatigue_multiplier(11), 1.25), "Restored fatigue multiplier is 1.25 on Day 11")
	_assert(es_restored.check_and_trigger_event(12, null, null, []).is_empty(), "Cooldown preserved after deserialize (Day 12 blocked since last_event_day=11)")
	_assert(is_equal_approx(es_restored.get_active_farm_modifier_bonus(12), 0.0), "Restored farm bonus expires cleanly on Day 12")
	_assert(is_equal_approx(es_restored.get_active_fatigue_multiplier(12), 1.25), "Restored heatwave remains active on Day 12")
	_assert(is_equal_approx(es_restored.get_active_fatigue_multiplier(13), 1.0), "Restored heatwave expires cleanly on Day 13")

	var restored_next_ev: Dictionary = es_restored.check_and_trigger_event(15, null, null, [])
	_assert(restored_next_ev.get("id", "") == ref_next_ev.get("id", ""), "Restored RNG state produces identical next scheduled event on Day 15 ('%s')" % str(restored_next_ev.get("id", "")))

	# Legacy empty dictionary resets cleanly to baseline
	es_restored.deserialize({}, 15)
	_assert(es_restored.last_event_day == -99 and not es_restored.is_farm_bonus_active(15) and not es_restored.is_heatwave_active(15), "Legacy empty deserialize resets timed modifiers and last_event_day to baseline")

	# Cleanup
	farmer.queue_free()
	cit_injured.queue_free()
	cit_nearly_full.queue_free()
	cit_dead_flag.queue_free()
	cit_zero_hp.queue_free()
	rm.queue_free()

	print("\n=== TestWorldEvents Summary: %d Passed, %d Failed ===" % [_passed, _failed])
	if _failed == 0:
		print("=== ALL WORLD EVENT INTEGRITY TESTS PASSED ===")
		quit(0)
	else:
		printerr("=== WORLD EVENT INTEGRITY TESTS FAILED (%d failures) ===" % _failed)
		quit(1)
