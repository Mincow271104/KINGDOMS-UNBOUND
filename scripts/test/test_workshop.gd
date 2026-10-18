extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1E: Dynamic Workshop
## Tests Workshop blueprint, build button, sprite, HUD (Metal & Tools), placement,
## real citizen metal smelting, real citizen tool crafting, real physical hauling,
## save/load persistence, buffer clamping, backward compatibility, and non-regression.

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")

var frame_count: int = 0
var world_instance: Node = null
var world_scene: PackedScene = null
var all_passed: bool = true

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1E DYNAMIC WORKSHOP TEST SUITE")
	print("========================================================\n")

	world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 3:
		var pass_tc1 := _test_tc_ws_1_blueprint_and_ui()
		var pass_tc2 := _test_tc_ws_2_placement_and_registration()
		var pass_tc3 := _test_tc_ws_3_citizen_metal_smelting()
		var pass_tc4 := _test_tc_ws_4_citizen_tool_crafting()
		var pass_tc5 := _test_tc_ws_5_physical_hauling()
		var pass_tc6 := _test_tc_ws_6_save_load_persistence()
		var pass_tc7 := _test_tc_ws_7_non_regression()

		all_passed = pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and pass_tc5 and pass_tc6 and pass_tc7

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL PACKAGE 1E DYNAMIC WORKSHOP TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 1E TESTS FAILED! (Exit Code 1)")
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

# -----------------------------------------------------------------------------
# TC-WS.1: Blueprint, Build Button, Sprite & HUD Verification (Fail Closed)
# -----------------------------------------------------------------------------
func _test_tc_ws_1_blueprint_and_ui() -> bool:
	print("--- Running TC-WS.1: Blueprint, Build Button, Sprite & HUD Verification ---")
	var failures: int = 0

	# 1. Blueprint validation in EconomyConfig
	var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("workshop", {})
	if bp.is_empty():
		printerr("  [FAIL] Blueprint 'workshop' not found in EconomyConfig.BLUEPRINTS!")
		return false

	if bp.get("footprint") != Vector2i(2, 2):
		printerr("  [FAIL] Workshop footprint is %s, expected (2, 2)" % bp.get("footprint"))
		failures += 1
	if bp.get("job_type") != "smith":
		printerr("  [FAIL] Workshop job_type is '%s', expected 'smith'" % bp.get("job_type"))
		failures += 1
	if bp.get("max_workers") != 4:
		printerr("  [FAIL] Workshop max_workers is %d, expected 4" % bp.get("max_workers"))
		failures += 1

	var cost: Dictionary = bp.get("cost", {})
	if cost.get(EconomyConfigScript.RES_WOOD, 0) != 20 or cost.get(EconomyConfigScript.RES_STONE, 0) != 15 or cost.get(EconomyConfigScript.RES_METAL, 0) != 5:
		printerr("  [FAIL] Workshop cost mismatch! Expected {wood: 20, stone: 15, metal: 5}, got: %s" % cost)
		failures += 1
	else:
		print("  [PASS] Blueprint 'workshop' verified: 2x2, 20 Wood + 15 Stone + 5 Metal, 4 Workers, smith role.")

	# 2. Recipe configuration
	var recipes: Dictionary = bp.get("recipes", {})
	if not recipes.has("smelt_metal") or not recipes.has("craft_tools"):
		printerr("  [FAIL] Workshop recipes missing required 'smelt_metal' or 'craft_tools'!")
		failures += 1
	else:
		var r_smelt = recipes["smelt_metal"]
		var r_craft = recipes["craft_tools"]
		if r_smelt.get("inputs", {}).get(EconomyConfigScript.RES_ORE, 0) != 2 or r_smelt.get("output") != EconomyConfigScript.RES_METAL or r_smelt.get("output_amount") != 1:
			printerr("  [FAIL] Smelt Metal recipe mismatch: inputs %s, output %s" % [r_smelt.get("inputs"), r_smelt.get("output")])
			failures += 1
		else:
			print("  [PASS] Recipe 'smelt_metal' verified: 2 Ore -> 1 Metal (duration 3.0h).")

		if r_craft.get("inputs", {}).get(EconomyConfigScript.RES_METAL, 0) != 2 or r_craft.get("inputs", {}).get(EconomyConfigScript.RES_WOOD, 0) != 1 or r_craft.get("output") != EconomyConfigScript.RES_TOOLS or r_craft.get("output_amount") != 1:
			printerr("  [FAIL] Craft Tools recipe mismatch: inputs %s, output %s" % [r_craft.get("inputs"), r_craft.get("output")])
			failures += 1
		else:
			print("  [PASS] Recipe 'craft_tools' verified: 2 Metal + 1 Wood -> 1 Tool (duration 3.0h).")

	# 3. Sprite asset check
	if not ResourceLoader.exists("res://assets/buildings/bld_workshop.png"):
		printerr("  [FAIL] 'res://assets/buildings/bld_workshop.png' does not exist!")
		failures += 1
	else:
		var tex: Texture2D = load("res://assets/buildings/bld_workshop.png")
		if tex == null:
			printerr("  [FAIL] Failed to load workshop texture!")
			failures += 1
		elif tex.get_width() != 64 or tex.get_height() != 48:
			printerr("  [FAIL] Workshop sprite size is %dx%d, expected 64x48!" % [tex.get_width(), tex.get_height()])
			failures += 1
		else:
			print("  [PASS] Workshop sprite verified: 64x48 px RGBA.")

	# 4. HUD integration (Fail Closed)
	var hud = world_instance.get("hud")
	if hud == null:
		printerr("  [FAIL] HUD instance not found on WorldView!")
		failures += 1
		return false

	var ws_btn = hud.get_node_or_null("BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/WorkshopBtn")
	if ws_btn == null:
		printerr("  [FAIL] WorkshopBtn not found in HUD BuildMenuPanel!")
		failures += 1
	else:
		if not "Xưởng Chế Tác" in ws_btn.text:
			printerr("  [FAIL] WorkshopBtn text '%s' missing Vietnamese name 'Xưởng Chế Tác'!" % ws_btn.text)
			failures += 1
		if not "20 Gỗ" in ws_btn.text or not "15 Đá" in ws_btn.text or not "5 Kim Loại" in ws_btn.text:
			printerr("  [FAIL] WorkshopBtn text '%s' missing cost info!" % ws_btn.text)
			failures += 1
		ws_btn.pressed.emit()
		if world_instance.get("placing_building_type") != "workshop":
			printerr("  [FAIL] WorkshopBtn did not activate 'workshop' placement! Current: '%s'" % world_instance.get("placing_building_type"))
			failures += 1
		else:
			print("  [PASS] WorkshopBtn verified and triggered building placement for 'workshop'.")
		world_instance.call("_cancel_placement")

	# 5. HUD Metal & Tools Resource Row Verification (Fail Closed)
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")
	if live_rm == null:
		printerr("  [FAIL] ResourceManager singleton unavailable in TC-WS.1!")
		failures += 1
		return false

	var metal_label = hud.get_node_or_null("TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/MetalLabel")
	var tools_label = hud.get_node_or_null("TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/ToolsLabel")

	if metal_label == null:
		printerr("  [FAIL] MetalLabel not found in HUD Resources row!")
		failures += 1
	else:
		var init_metal: int = live_rm.get_available_stock("metal")
		var expected_metal_text := "⚔️ Kim loại: %d" % init_metal
		if metal_label.text != expected_metal_text:
			printerr("  [FAIL] MetalLabel text '%s' != expected '%s'!" % [metal_label.text, expected_metal_text])
			failures += 1
		else:
			print("  [PASS] MetalLabel accurately displays ResourceManager available stock: '%s'." % metal_label.text)

		# Dynamic update test for metal
		live_rm.add_resource("metal", 15)
		if metal_label.text != "⚔️ Kim loại: %d" % live_rm.get_available_stock("metal"):
			printerr("  [FAIL] MetalLabel did not update dynamically after adding 15 metal!")
			failures += 1
		live_rm.consume_resource("metal", 15)
		if metal_label.text != expected_metal_text:
			printerr("  [FAIL] MetalLabel did not restore after consuming metal!")
			failures += 1

	if tools_label == null:
		printerr("  [FAIL] ToolsLabel not found in HUD Resources row!")
		failures += 1
	else:
		var init_tools: int = live_rm.get_available_stock("tools")
		var expected_tools_text := "🛠️ Công cụ: %d" % init_tools
		if tools_label.text != expected_tools_text:
			printerr("  [FAIL] ToolsLabel text '%s' != expected '%s'!" % [tools_label.text, expected_tools_text])
			failures += 1
		else:
			print("  [PASS] ToolsLabel accurately displays ResourceManager available stock: '%s'." % tools_label.text)

		# Dynamic update test for tools
		live_rm.add_resource("tools", 10)
		if tools_label.text != "🛠️ Công cụ: %d" % live_rm.get_available_stock("tools"):
			printerr("  [FAIL] ToolsLabel did not update dynamically after adding 10 tools!")
			failures += 1
		live_rm.consume_resource("tools", 10)
		if tools_label.text != expected_tools_text:
			printerr("  [FAIL] ToolsLabel did not restore after consuming tools!")
			failures += 1

	# 6. Verify existing resource labels and building buttons remain present
	var expected_labels: Array[String] = ["FoodLabel", "WoodLabel", "StoneLabel", "OreLabel", "GoldLabel", "PopLabel"]
	for lbl_name in expected_labels:
		var lbl = hud.get_node_or_null("TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/" + lbl_name)
		if lbl == null:
			printerr("  [FAIL] Existing HUD label '%s' missing!" % lbl_name)
			failures += 1

	var expected_buttons: Array[String] = ["HouseBtn", "StorehouseBtn", "FarmBtn", "WoodcutterBtn", "WatchtowerBtn", "QuarryBtn", "MineBtn"]
	for btn_name in expected_buttons:
		var btn = hud.get_node_or_null("BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/" + btn_name)
		if btn == null:
			printerr("  [FAIL] Existing build button '%s' missing!" % btn_name)
			failures += 1

	# 7. Citizen inspector Smith role option
	var role_opt: OptionButton = hud.get_node_or_null("CitizenInspectPanel/MarginContainer/VBoxContainer/RoleHBox/RoleOptionBtn")
	if role_opt == null:
		printerr("  [FAIL] RoleOptionBtn not found in CitizenInspectPanel!")
		failures += 1
	else:
		var found_smith := false
		for idx in range(role_opt.item_count):
			if "Smith" in role_opt.get_item_text(idx) or "Xưởng" in role_opt.get_item_text(idx):
				found_smith = true
				break
		if not found_smith:
			printerr("  [FAIL] Smith role not found in RoleOptionBtn items!")
			failures += 1
		else:
			print("  [PASS] Smith worker role present in citizen inspector options.")

	if failures == 0:
		print("  [PASS] TC-WS.1 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-WS.1 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-WS.2: Placement, Access Cell & Dynamic Registration
# -----------------------------------------------------------------------------
func _test_tc_ws_2_placement_and_registration() -> bool:
	print("--- Running TC-WS.2: Placement, Access Cell & Dynamic Registration ---")
	var failures: int = 0

	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")
	var world_data = world_instance.get("world_data")
	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")

	if live_rm == null or world_data == null or wp_mgr == null or job_mgr == null:
		printerr("  [FAIL] Subsystem singletons or data null in TC-WS.2!")
		return false

	live_rm.add_resource("wood", 100)
	live_rm.add_resource("stone", 100)
	live_rm.add_resource("metal", 50)

	# 1. Clear grass patch for Workshop at (26, 23) (2x2)
	var ws_origin := Vector2i(26, 23)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := ws_origin + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	var wood_prior: int = live_rm.get_available_stock("wood")
	var stone_prior: int = live_rm.get_available_stock("stone")
	var metal_prior: int = live_rm.get_available_stock("metal")

	# Place Workshop at legal position (26, 23)
	world_instance.set("placing_building_type", "workshop")
	var place_res: Dictionary = world_instance.call("_execute_placement", ws_origin)
	world_instance.call("complete_construction", "bld_workshop_26_23")

	if not place_res.get("success", false):
		printerr("  [FAIL] Failed to place workshop at (26, 23): %s" % place_res.get("reason", "unknown"))
		return false

	# 2. Verify atomic cost deduction (20 Wood, 15 Stone, 5 Metal)
	var wood_post: int = live_rm.get_available_stock("wood")
	var stone_post: int = live_rm.get_available_stock("stone")
	var metal_post: int = live_rm.get_available_stock("metal")

	if wood_post != wood_prior - 20 or stone_post != stone_prior - 15 or metal_post != metal_prior - 5:
		printerr("  [FAIL] Cost deduction incorrect! Wood: %d->%d (-20), Stone: %d->%d (-15), Metal: %d->%d (-5)" % [wood_prior, wood_post, stone_prior, stone_post, metal_prior, metal_post])
		failures += 1
	else:
		print("  [PASS] Workshop costs deducted atomically (-20 Wood, -15 Stone, -5 Metal).")

	# 3. Verify Dynamic Workplace channels registration against EconomyConfig recipe definitions
	var b_id := "bld_workshop_26_23"
	var ws_bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("workshop", {})
	var ws_recipes: Dictionary = ws_bp.get("recipes", {})
	var cfg_smelt: Dictionary = ws_recipes.get("smelt_metal", {})
	var cfg_craft: Dictionary = ws_recipes.get("craft_tools", {})

	var smelt_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace(b_id + "_smelt")
	var craft_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace(b_id + "_craft")

	if smelt_wp == null:
		printerr("  [FAIL] Smelt Metal channel '%s_smelt' not registered in WorkplaceManager!" % b_id)
		failures += 1
		return false
	if craft_wp == null:
		printerr("  [FAIL] Craft Tools channel '%s_craft' not registered in WorkplaceManager!" % b_id)
		failures += 1
		return false

	# Validate smelt_wp against cfg_smelt
	if smelt_wp.output_resource != cfg_smelt.get("output", "") or smelt_wp.buffer_capacity != cfg_smelt.get("buffer_capacity", 0) or smelt_wp.worker_quota != cfg_smelt.get("worker_quota", 0) or smelt_wp.recipe_id != "smelt_metal" or smelt_wp.output_amount != cfg_smelt.get("output_amount", 0) or smelt_wp.required_inputs != cfg_smelt.get("inputs", {}):
		printerr("  [FAIL] Smelt channel does not match EconomyConfig recipe! Wp: out=%s cap=%d quota=%d inputs=%s, Cfg: %s" % [smelt_wp.output_resource, smelt_wp.buffer_capacity, smelt_wp.worker_quota, smelt_wp.required_inputs, cfg_smelt])
		failures += 1
	else:
		print("  [PASS] Smelt channel registered strictly from EconomyConfig recipe (out: %s, cap: %d, quota: %d, inputs: %s)." % [smelt_wp.output_resource, smelt_wp.buffer_capacity, smelt_wp.worker_quota, smelt_wp.required_inputs])

	# Validate craft_wp against cfg_craft
	if craft_wp.output_resource != cfg_craft.get("output", "") or craft_wp.buffer_capacity != cfg_craft.get("buffer_capacity", 0) or craft_wp.worker_quota != cfg_craft.get("worker_quota", 0) or craft_wp.recipe_id != "craft_tools" or craft_wp.output_amount != cfg_craft.get("output_amount", 0) or craft_wp.required_inputs != cfg_craft.get("inputs", {}):
		printerr("  [FAIL] Craft channel does not match EconomyConfig recipe! Wp: out=%s cap=%d quota=%d inputs=%s, Cfg: %s" % [craft_wp.output_resource, craft_wp.buffer_capacity, craft_wp.worker_quota, craft_wp.required_inputs, cfg_craft])
		failures += 1
	else:
		print("  [PASS] Craft channel registered strictly from EconomyConfig recipe (out: %s, cap: %d, quota: %d, inputs: %s)." % [craft_wp.output_resource, craft_wp.buffer_capacity, craft_wp.worker_quota, craft_wp.required_inputs])

	# Check access cell
	var acc: Vector2i = smelt_wp.access_cell
	if acc == Vector2i(-1, -1):
		printerr("  [FAIL] Workshop access_cell is invalid (-1, -1)!")
		failures += 1
	else:
		var in_footprint := (acc.x >= 26 and acc.x < 28 and acc.y >= 23 and acc.y < 25)
		if in_footprint:
			printerr("  [FAIL] Workshop access cell %s is inside the 2x2 footprint!" % acc)
			failures += 1
		elif world_data.occupancy[acc.x][acc.y]:
			printerr("  [FAIL] Workshop access cell %s is occupied!" % acc)
			failures += 1
		else:
			print("  [PASS] Workshop registered with valid walkable perimeter access cell: %s" % acc)

	# 4. Verify recurring jobs against configured recipe quotas and durations
	var ws_jobs := job_mgr.get_jobs_for_building(b_id)
	var expected_total_jobs: int = int(cfg_smelt.get("worker_quota", 2)) + int(cfg_craft.get("worker_quota", 2))
	if ws_jobs.size() != expected_total_jobs:
		printerr("  [FAIL] Expected %d jobs for '%s', got %d" % [expected_total_jobs, b_id, ws_jobs.size()])
		failures += 1
	else:
		var smelt_jobs := 0
		var craft_jobs := 0
		var expected_smelt_duration: float = float(cfg_smelt.get("duration_hours", 3.0))
		var expected_craft_duration: float = float(cfg_craft.get("duration_hours", 3.0))
		for j in ws_jobs:
			if j.type == ws_bp.get("job_type", "smith") and j.is_recurring and j.target_cell == acc:
				if j.recipe_id == "smelt_metal" and is_equal_approx(j.work_hours_required, expected_smelt_duration) and j.workplace_channel_id == b_id + "_smelt":
					smelt_jobs += 1
				elif j.recipe_id == "craft_tools" and is_equal_approx(j.work_hours_required, expected_craft_duration) and j.workplace_channel_id == b_id + "_craft":
					craft_jobs += 1
		if smelt_jobs != cfg_smelt.get("worker_quota", 2) or craft_jobs != cfg_craft.get("worker_quota", 2):
			printerr("  [FAIL] Job channel distribution mismatch: %d smelt, %d craft (expected %d, %d)!" % [smelt_jobs, craft_jobs, cfg_smelt.get("worker_quota", 2), cfg_craft.get("worker_quota", 2)])
			failures += 1
		else:
			print("  [PASS] Recurring jobs match recipe config: %d Smelt Metal (%s h) + %d Craft Tools (%s h) at %s." % [smelt_jobs, expected_smelt_duration, craft_jobs, expected_craft_duration, acc])

	# 5. Inaccessible Workshop placement rejection before cost deduction
	var walled_origin := Vector2i(14, 14)
	for ox in range(-1, 3):
		for oy in range(-1, 3):
			var c := walled_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(c):
				world_data.occupancy[c.x][c.y] = true

	for ox in range(2):
		for oy in range(2):
			world_data.occupancy[walled_origin.x + ox][walled_origin.y + oy] = false

	var wood_before_inacc: int = live_rm.get_available_stock("wood")
	world_instance.set("placing_building_type", "workshop")
	var inacc_res: Dictionary = world_instance.call("_execute_placement", walled_origin)

	if inacc_res.get("success", false):
		printerr("  [FAIL] Workshop placed on inaccessible site!")
		failures += 1
	elif live_rm.get_available_stock("wood") != wood_before_inacc:
		printerr("  [FAIL] Resources deducted despite inaccessible placement rejection!")
		failures += 1
	else:
		print("  [PASS] Inaccessible Workshop placement rejected before cost deduction.")

	world_instance.call("_cancel_placement")

	# Clean up walled site
	for ox in range(-1, 3):
		for oy in range(-1, 3):
			var c := walled_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(c):
				world_data.occupancy[c.x][c.y] = false

	if failures == 0:
		print("  [PASS] TC-WS.2 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-WS.2 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-WS.3: Real Citizen Metal Smelting Integration
# -----------------------------------------------------------------------------
func _test_tc_ws_3_citizen_metal_smelting() -> bool:
	print("--- Running TC-WS.3: Real Citizen Metal Smelting Integration ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var nav: GridNavigation = world_instance.get("nav")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	# Isolate execution: set existing citizens to idle
	for cit in world_instance.get("citizen_list"):
		cit.role = "idle"
		if cit.active_job != null:
			job_mgr.release_job(cit.active_job)
			cit.active_job = null
			cit.current_state = CitizenControllerScript.State.IDLE

	var smelt_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_smelt")
	if smelt_wp == null:
		printerr("  [FAIL] bld_workshop_26_23_smelt not found!")
		return false
	smelt_wp.buffer_amount = 0

	# Prepare resources: ensure at least 10 Ore
	live_rm.add_resource("ore", 20)

	# 1. Create real citizen with role "smith"
	var smith: CitizenController = CitizenControllerScript.new()
	smith.name = "test_smith_smelter"
	world_instance.add_child(smith)
	smith.init_citizen(
		"test_smith_smelter",
		"Trương Luyện Kim",
		"smith",
		Vector2i(25, 23),
		nav,
		job_mgr,
		wp_mgr
	)

	# 2. Cycle 1: Request job via state machine
	smith._process(0.1)

	if smith.active_job == null:
		printerr("  [FAIL] Real smith failed to claim a job!")
		failures += 1
		smith.free()
		return false

	print("  [PASS] Smith claimed job: '%s' (recipe: %s, target: %s)." % [smith.active_job.id, smith.active_job.recipe_id, smith.active_job.target_building_id])

	# 3. Move along discrete path to access cell
	var move_steps := 0
	while smith.current_state == CitizenControllerScript.State.MOVING_TO_JOB and move_steps < 30:
		move_steps += 1
		smith._process(0.2)

	if smith.current_state != CitizenControllerScript.State.WORKING:
		printerr("  [FAIL] Smith failed to enter WORKING state! Current: %d" % smith.current_state)
		failures += 1
	if smith.current_cell != smelt_wp.access_cell:
		printerr("  [FAIL] Smith arrived at %s, expected %s" % [smith.current_cell, smelt_wp.access_cell])
		failures += 1
	print("  [PASS] Smith moved along grid and arrived at access cell %s (State: WORKING)." % smelt_wp.access_cell)

	# 4. Work 3.0 hours to complete cycle 1
	var ore_prior: int = live_rm.get_available_stock("ore")
	var metal_prior: int = live_rm.get_available_stock("metal")
	smith._process(3.0)

	# Assertions: 2 Ore consumed, 1 Metal deposited to local buffer, central metal unchanged
	var ore_post: int = live_rm.get_available_stock("ore")
	var metal_post: int = live_rm.get_available_stock("metal")

	if ore_post != ore_prior - 2:
		printerr("  [FAIL] Ore not consumed atomically! Prior: %d, Post: %d (expected -2)" % [ore_prior, ore_post])
		failures += 1
	else:
		print("  [PASS] Exactly 2 Ore consumed atomically on metal smelting cycle.")

	if smelt_wp.buffer_amount != 1:
		printerr("  [FAIL] Smelt buffer is %d, expected 1!" % smelt_wp.buffer_amount)
		failures += 1
	else:
		print("  [PASS] Exactly 1 Metal deposited directly into local workshop buffer.")

	if metal_post != metal_prior:
		printerr("  [FAIL] Central metal stock changed before hauling! Prior: %d, Post: %d" % [metal_prior, metal_post])
		failures += 1
	else:
		print("  [PASS] Central metal stock strictly unchanged on production (Zero Teleportation verified).")

	# 5. Test insufficient Ore: consume all Ore to 0
	live_rm.consume_resource("ore", live_rm.get_available_stock("ore"))
	if smith.active_job != null:
		job_mgr.release_job(smith.active_job)
		smith.active_job = null

	var smelt_job: JobManager.JobData = null
	for j in job_mgr.get_jobs_for_building("bld_workshop_26_23"):
		if j.recipe_id == "smelt_metal":
			smelt_job = j
			break

	if smelt_job != null:
		var can_exec := job_mgr._is_job_executable(smelt_job, wp_mgr, live_rm)
		if can_exec:
			printerr("  [FAIL] Smelt job reported executable with 0 Ore!")
			failures += 1
		else:
			print("  [PASS] Smelt job correctly marked non-executable when Ore is 0.")

		# Test genuine completion and rejection when citizen works on smelt job with 0 ore
		smelt_job.state = JobManager.JobState.IN_PROGRESS
		smelt_job.work_hours_done = 0.0
		smelt_job.worker_id = smith.citizen_id
		smith.active_job = smelt_job
		smith.current_state = CitizenControllerScript.State.WORKING
		smith.current_cell = smelt_wp.access_cell
		var ore_before_no_ore = live_rm.get_available_stock("ore")
		var buf_before_no_ore = smelt_wp.buffer_amount
		var metal_before_no_ore = live_rm.get_available_stock("metal")

		smith._process(3.0)

		# Verify completion cycle was genuinely executed through CitizenController._process_working:
		if smith.current_state != CitizenControllerScript.State.IDLE or smith.active_job != null:
			printerr("  [FAIL] Smith did not complete 0-ore work cycle to IDLE! State: %d, job: %s" % [smith.current_state, smith.active_job])
			failures += 1
		if not ("Thiếu nguyên liệu" in smith.status_reason):
			printerr("  [FAIL] Smith status_reason '%s' did not report missing ingredients!" % smith.status_reason)
			failures += 1
		if live_rm.get_available_stock("ore") != ore_before_no_ore or smelt_wp.buffer_amount != buf_before_no_ore or live_rm.get_available_stock("metal") != metal_before_no_ore:
			printerr("  [FAIL] Production occurred with 0 Ore! Ore: %d->%d, Buf: %d->%d" % [ore_before_no_ore, live_rm.get_available_stock("ore"), buf_before_no_ore, smelt_wp.buffer_amount])
			failures += 1
		else:
			print("  [PASS] Insufficient Ore work cycle genuinely executed and rejected: 0 Ore consumed, 0 Metal produced, reason: '%s'." % smith.status_reason)

	# 6. Test full buffer: restore Ore, fill buffer to capacity (40)
	live_rm.add_resource("ore", 20)
	smelt_wp.buffer_amount = smelt_wp.buffer_capacity
	if smelt_job != null:
		var can_exec_full := job_mgr._is_job_executable(smelt_job, wp_mgr, live_rm)
		if can_exec_full:
			printerr("  [FAIL] Smelt job reported executable when buffer is full (%d)!" % smelt_wp.buffer_capacity)
			failures += 1
		else:
			print("  [PASS] Smelt job correctly marked non-executable when buffer is full (%d)." % smelt_wp.buffer_capacity)

		# Real citizen working execution with full buffer
		smelt_job.state = JobManager.JobState.IN_PROGRESS
		smelt_job.work_hours_done = 0.0
		smelt_job.worker_id = smith.citizen_id
		smith.active_job = smelt_job
		smith.current_state = CitizenControllerScript.State.WORKING
		smith.current_cell = smelt_wp.access_cell
		var ore_before_full = live_rm.get_available_stock("ore")

		smith._process(3.0)

		# Verify completion cycle was genuinely executed through CitizenController._process_working:
		if smith.current_state != CitizenControllerScript.State.IDLE or smith.active_job != null:
			printerr("  [FAIL] Smith did not complete full-buffer work cycle to IDLE! State: %d, job: %s" % [smith.current_state, smith.active_job])
			failures += 1
		if not ("đầy" in smith.status_reason):
			printerr("  [FAIL] Smith status_reason '%s' did not report full buffer!" % smith.status_reason)
			failures += 1
		if smelt_wp.buffer_amount != smelt_wp.buffer_capacity or live_rm.get_available_stock("ore") != ore_before_full:
			printerr("  [FAIL] Full buffer violated or inputs consumed on full buffer! Buf: %d, Ore: %d->%d" % [smelt_wp.buffer_amount, ore_before_full, live_rm.get_available_stock("ore")])
			failures += 1
		else:
			print("  [PASS] Full buffer (%d) work cycle genuinely executed and clamped safely: 0 Ore consumed, buffer at capacity, reason: '%s'." % [smelt_wp.buffer_capacity, smith.status_reason])

	# Clean up
	if smith.active_job != null:
		job_mgr.release_job(smith.active_job)
		smith.active_job = null
	for j in job_mgr.get_jobs_for_building("bld_workshop_26_23"):
		j.state = JobManager.JobState.AVAILABLE
		j.worker_id = ""
		j.work_hours_done = 0.0
	if smith.get_parent():
		smith.get_parent().remove_child(smith)
	smith.free()

	if failures == 0:
		print("  [PASS] TC-WS.3 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-WS.3 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-WS.4: Real Citizen Tool Crafting Integration
# -----------------------------------------------------------------------------
func _test_tc_ws_4_citizen_tool_crafting() -> bool:
	print("--- Running TC-WS.4: Real Citizen Tool Crafting Integration ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var nav: GridNavigation = world_instance.get("nav")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	var craft_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_craft")
	if craft_wp == null:
		printerr("  [FAIL] bld_workshop_26_23_craft not found!")
		return false
	craft_wp.buffer_amount = 0

	# Provide required ingredients: Metal >= 10, Wood >= 10
	live_rm.add_resource("metal", 20)
	live_rm.add_resource("wood", 20)

	# Ensure all workshop recurring jobs are clean and AVAILABLE
	for j in job_mgr.get_jobs_for_building("bld_workshop_26_23"):
		j.state = JobManager.JobState.AVAILABLE
		j.worker_id = ""
		j.work_hours_done = 0.0

	# 1. Create real citizen with role "smith"
	var smith: CitizenController = CitizenControllerScript.new()
	smith.name = "test_smith_crafter"
	world_instance.add_child(smith)
	smith.init_citizen(
		"test_smith_crafter",
		"Vũ Rèn Công Cụ",
		"smith",
		Vector2i(25, 23),
		nav,
		job_mgr,
		wp_mgr
	)

	# Find or assign a craft_tools job
	var craft_job: JobManager.JobData = null
	for j in job_mgr.get_jobs_for_building("bld_workshop_26_23"):
		if j.recipe_id == "craft_tools" and j.state == JobManager.JobState.AVAILABLE:
			craft_job = j
			break

	if craft_job == null:
		printerr("  [FAIL] No available craft_tools job found!")
		failures += 1
		smith.free()
		return false

	craft_job.state = JobManager.JobState.RESERVED
	craft_job.worker_id = smith.citizen_id
	smith.active_job = craft_job
	smith.current_state = CitizenControllerScript.State.MOVING_TO_JOB
	smith.current_path = nav.find_path(smith.current_cell, craft_job.target_cell)

	# Move to access cell
	var move_steps := 0
	while smith.current_state == CitizenControllerScript.State.MOVING_TO_JOB and move_steps < 30:
		move_steps += 1
		smith._process(0.2)

	if smith.current_state != CitizenControllerScript.State.WORKING:
		printerr("  [FAIL] Smith failed to enter WORKING state for tool crafting!")
		failures += 1

	# Complete work cycle
	var metal_prior: int = live_rm.get_available_stock("metal")
	var wood_prior: int = live_rm.get_available_stock("wood")
	var tools_prior: int = live_rm.get_available_stock("tools")

	smith._process(3.0)

	# Assertions: 2 Metal and 1 Wood consumed, 1 Tool deposited to buffer, central tools unchanged
	var metal_post: int = live_rm.get_available_stock("metal")
	var wood_post: int = live_rm.get_available_stock("wood")
	var tools_post: int = live_rm.get_available_stock("tools")

	if metal_post != metal_prior - 2 or wood_post != wood_prior - 1:
		printerr("  [FAIL] Tool crafting inputs not consumed atomically! Metal: %d->%d (-2), Wood: %d->%d (-1)" % [metal_prior, metal_post, wood_prior, wood_post])
		failures += 1
	else:
		print("  [PASS] Exactly 2 Metal and 1 Wood consumed atomically on tool crafting cycle.")

	if craft_wp.buffer_amount != 1:
		printerr("  [FAIL] Craft tools buffer is %d, expected 1!" % craft_wp.buffer_amount)
		failures += 1
	else:
		print("  [PASS] Exactly 1 Tool deposited directly into local workshop tools buffer.")

	if tools_post != tools_prior:
		printerr("  [FAIL] Central tools stock changed before hauling! Prior: %d, Post: %d" % [tools_prior, tools_post])
		failures += 1
	else:
		print("  [PASS] Central tools stock strictly unchanged on production (Zero Teleportation verified).")

	# 2. Test missing ingredient: 0 Wood (Atomic rejection on genuine work cycle completion)
	live_rm.consume_resource("wood", live_rm.get_available_stock("wood"))
	craft_job.state = JobManager.JobState.IN_PROGRESS
	craft_job.work_hours_done = 0.0
	craft_job.worker_id = smith.citizen_id
	smith.active_job = craft_job
	smith.current_state = CitizenControllerScript.State.WORKING
	smith.current_cell = craft_wp.access_cell

	var metal_before_no_wood = live_rm.get_available_stock("metal")
	var tools_before_no_wood = live_rm.get_available_stock("tools")
	var craft_buf_before = craft_wp.buffer_amount

	smith._process(3.0)

	# Verify work cycle genuinely completed and reached atomic rejection path:
	if smith.current_state != CitizenControllerScript.State.IDLE or smith.active_job != null:
		printerr("  [FAIL] Smith did not complete missing wood work cycle to IDLE! State: %d, job: %s" % [smith.current_state, smith.active_job])
		failures += 1

	if not ("Thiếu nguyên liệu" in smith.status_reason):
		printerr("  [FAIL] Smith status_reason '%s' did not report missing ingredients!" % smith.status_reason)
		failures += 1

	if live_rm.get_available_stock("metal") != metal_before_no_wood:
		printerr("  [FAIL] Partial ingredient consumption: Metal changed from %d to %d when Wood was 0!" % [metal_before_no_wood, live_rm.get_available_stock("metal")])
		failures += 1
	elif craft_wp.buffer_amount != craft_buf_before:
		printerr("  [FAIL] Tools buffer changed from %d to %d without Wood!" % [craft_buf_before, craft_wp.buffer_amount])
		failures += 1
	elif live_rm.get_available_stock("tools") != tools_before_no_wood:
		printerr("  [FAIL] Central tools stock changed without Wood!")
		failures += 1
	else:
		print("  [PASS] Atomic rejection verified on completed cycle: 0 Metal consumed when Wood is missing (Buffer: %d, reason: '%s')." % [craft_wp.buffer_amount, smith.status_reason])

	# Clean up
	live_rm.add_resource("wood", 20)
	if smith.active_job != null:
		job_mgr.release_job(smith.active_job)
		smith.active_job = null
	for j in job_mgr.get_jobs_for_building("bld_workshop_26_23"):
		j.state = JobManager.JobState.AVAILABLE
		j.worker_id = ""
		j.work_hours_done = 0.0
	if smith.get_parent():
		smith.get_parent().remove_child(smith)
	smith.free()

	if failures == 0:
		print("  [PASS] TC-WS.4 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-WS.4 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-WS.5: Real Physical Hauling (Metal & Tools Independently)
# -----------------------------------------------------------------------------
func _test_tc_ws_5_physical_hauling() -> bool:
	print("--- Running TC-WS.5: Real Physical Hauling (Metal & Tools Independently) ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var nav: GridNavigation = world_instance.get("nav")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")
	var hud = world_instance.get("hud")

	var smelt_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_smelt")
	var craft_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_craft")

	# -------------------- PART A: Metal Hauling --------------------
	smelt_wp.buffer_amount = 8
	var created_jobs := wp_mgr.update_hauling_jobs(job_mgr)
	if created_jobs < 1:
		printerr("  [FAIL] No hauling job created for metal buffer amount 8!")
		failures += 1
		return false

	var metal_haul_job: JobManager.JobData = null
	for j in job_mgr.get_all_jobs():
		if j.type == "hauler" and j.cargo_resource == "metal" and j.state == JobManager.JobState.AVAILABLE:
			metal_haul_job = j
			break

	if metal_haul_job == null:
		printerr("  [FAIL] Metal hauling job not found!")
		failures += 1
		return false

	var hauler: CitizenController = CitizenControllerScript.new()
	hauler.name = "metal_hauler"
	world_instance.add_child(hauler)
	hauler.init_citizen("metal_hauler", "Phan Vận Chuyển Kim Loại", "hauler", Vector2i(25, 23), nav, job_mgr, wp_mgr)

	hauler._process(0.1) # Claims job
	if hauler.active_job != metal_haul_job:
		printerr("  [FAIL] Hauler failed to claim metal hauling job!")
		failures += 1

	var metal_central_before_pickup: int = live_rm.get_available_stock("metal")
	var buf_before_pickup: int = smelt_wp.buffer_amount

	# Travel to source cell
	var steps := 0
	while hauler.current_state == CitizenControllerScript.State.MOVING_TO_JOB and steps < 30:
		steps += 1
		hauler._process(0.2)

	# Verify post-pickup
	if smelt_wp.buffer_amount != buf_before_pickup - 8:
		printerr("  [FAIL] Metal buffer not decremented upon pickup! Was %d, now %d" % [buf_before_pickup, smelt_wp.buffer_amount])
		failures += 1
	if hauler.carrying_resource != "metal" or hauler.carrying_amount != 8:
		printerr("  [FAIL] Hauler cargo mismatch! Carrying: %d %s" % [hauler.carrying_amount, hauler.carrying_resource])
		failures += 1
	if live_rm.get_available_stock("metal") != metal_central_before_pickup:
		printerr("  [FAIL] Central metal stock changed upon pickup!")
		failures += 1
	else:
		print("  [PASS] Metal cargo (8) picked up: buffer decremented, central stock strictly unchanged.")

	# Travel to dropoff
	steps = 0
	while hauler.current_state == CitizenControllerScript.State.HAULING and steps < 60:
		steps += 1
		hauler._process(0.2)
		if hauler.current_state == CitizenControllerScript.State.HAULING:
			if live_rm.get_available_stock("metal") != metal_central_before_pickup:
				printerr("  [FAIL] Central metal stock changed during transit!")
				failures += 1

	# Post-delivery verification
	var metal_central_post_delivery: int = live_rm.get_available_stock("metal")
	if metal_central_post_delivery != metal_central_before_pickup + 8:
		printerr("  [FAIL] Central metal stock not credited! Expected %d, got %d" % [metal_central_before_pickup + 8, metal_central_post_delivery])
		failures += 1
	else:
		print("  [PASS] Metal delivered physically to central storage (+8 Metal credited).")

	var metal_lbl = hud.get_node_or_null("TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/MetalLabel")
	if metal_lbl == null:
		printerr("  [FAIL] MetalLabel missing post-delivery!")
		failures += 1
	elif metal_lbl.text != "⚔️ Kim loại: %d" % metal_central_post_delivery:
		printerr("  [FAIL] MetalLabel text '%s' does not match post-delivery stock %d!" % [metal_lbl.text, metal_central_post_delivery])
		failures += 1
	else:
		print("  [PASS] HUD MetalLabel dynamically updated post-delivery: '%s'." % metal_lbl.text)

	if hauler.get_parent():
		hauler.get_parent().remove_child(hauler)
	hauler.free()

	# -------------------- PART B: Tools Hauling --------------------
	craft_wp.buffer_amount = 6
	wp_mgr.update_hauling_jobs(job_mgr)

	var tools_haul_job: JobManager.JobData = null
	for j in job_mgr.get_all_jobs():
		if j.type == "hauler" and j.cargo_resource == "tools" and j.state == JobManager.JobState.AVAILABLE:
			tools_haul_job = j
			break

	if tools_haul_job == null:
		printerr("  [FAIL] Tools hauling job not found!")
		failures += 1
		return false

	var hauler_tools: CitizenController = CitizenControllerScript.new()
	hauler_tools.name = "tools_hauler"
	world_instance.add_child(hauler_tools)
	hauler_tools.init_citizen("tools_hauler", "Bùi Vận Chuyển Công Cụ", "hauler", Vector2i(25, 23), nav, job_mgr, wp_mgr)

	hauler_tools._process(0.1) # Claims job
	var tools_central_before_pickup: int = live_rm.get_available_stock("tools")
	var buf_tools_before_pickup: int = craft_wp.buffer_amount

	# Travel to source cell
	steps = 0
	while hauler_tools.current_state == CitizenControllerScript.State.MOVING_TO_JOB and steps < 30:
		steps += 1
		hauler_tools._process(0.2)

	# Verify post-pickup
	if craft_wp.buffer_amount != buf_tools_before_pickup - 6:
		printerr("  [FAIL] Tools buffer not decremented upon pickup! Amount: %d, expected %d" % [craft_wp.buffer_amount, buf_tools_before_pickup - 6])
		failures += 1
	if hauler_tools.carrying_resource != "tools" or hauler_tools.carrying_amount != 6:
		printerr("  [FAIL] Tools cargo mismatch! Carrying: %d %s" % [hauler_tools.carrying_amount, hauler_tools.carrying_resource])
		failures += 1
	if live_rm.get_available_stock("tools") != tools_central_before_pickup:
		printerr("  [FAIL] Central tools stock changed upon pickup! Prior: %d, current: %d" % [tools_central_before_pickup, live_rm.get_available_stock("tools")])
		failures += 1
	else:
		print("  [PASS] Tools cargo (6) picked up: buffer decremented, central stock strictly unchanged.")

	# Travel to dropoff (assert central tools remains strictly unchanged during transit)
	steps = 0
	while hauler_tools.current_state == CitizenControllerScript.State.HAULING and steps < 60:
		steps += 1
		hauler_tools._process(0.2)
		if hauler_tools.current_state == CitizenControllerScript.State.HAULING:
			if live_rm.get_available_stock("tools") != tools_central_before_pickup:
				printerr("  [FAIL] Central tools stock changed during transit! Expected %d, got %d" % [tools_central_before_pickup, live_rm.get_available_stock("tools")])
				failures += 1

	# Post-delivery verification
	if hauler_tools.carrying_amount != 0 or hauler_tools.carrying_resource != "":
		printerr("  [FAIL] Tools cargo not cleared from hauler after delivery! Remaining: %d %s" % [hauler_tools.carrying_amount, hauler_tools.carrying_resource])
		failures += 1
	if tools_haul_job.state != JobManager.JobState.COMPLETED:
		printerr("  [FAIL] Tools hauling job not marked COMPLETED! Current state: %d" % tools_haul_job.state)
		failures += 1
	else:
		print("  [PASS] Tools cargo cleanly cleared and hauling job marked COMPLETED.")

	var tools_central_post_delivery: int = live_rm.get_available_stock("tools")
	if tools_central_post_delivery != tools_central_before_pickup + 6:
		printerr("  [FAIL] Central tools stock not credited! Expected %d, got %d" % [tools_central_before_pickup + 6, tools_central_post_delivery])
		failures += 1
	else:
		print("  [PASS] Tools delivered physically to central storage (+6 Tools credited).")

	var tools_lbl = hud.get_node_or_null("TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/ToolsLabel")
	if tools_lbl == null:
		printerr("  [FAIL] ToolsLabel missing post-delivery!")
		failures += 1
	elif tools_lbl.text != "🛠️ Công cụ: %d" % tools_central_post_delivery:
		printerr("  [FAIL] ToolsLabel text '%s' does not match post-delivery stock %d!" % [tools_lbl.text, tools_central_post_delivery])
		failures += 1
	else:
		print("  [PASS] HUD ToolsLabel dynamically updated post-delivery: '%s'." % tools_lbl.text)

	if hauler_tools.get_parent():
		hauler_tools.get_parent().remove_child(hauler_tools)
	hauler_tools.free()

	if failures == 0:
		print("  [PASS] TC-WS.5 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-WS.5 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-WS.6: Save/Load, Buffer Restoration & Clamping Integrity
# -----------------------------------------------------------------------------
func _test_tc_ws_6_save_load_persistence() -> bool:
	print("--- Running TC-WS.6: Save/Load, Buffer Restoration & Clamping Integrity ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

	var smelt_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_smelt")
	var craft_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_craft")

	if smelt_wp == null or craft_wp == null:
		printerr("  [FAIL] Workshop channels not available for TC-WS.6!")
		return false

	# 1. Set distinct buffer amounts
	smelt_wp.buffer_amount = 14
	craft_wp.buffer_amount = 9

	# 2. Serialize world state
	var saved_state: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	var wp_saved: Dictionary = saved_state.get("workplaces", {})

	if not wp_saved.has("bld_workshop_26_23_smelt") or not wp_saved.has("bld_workshop_26_23_craft"):
		printerr("  [FAIL] Serialized state missing workshop recipe channels!")
		failures += 1
	else:
		if wp_saved["bld_workshop_26_23_smelt"].get("buffer_amount") != 14:
			printerr("  [FAIL] Saved smelt buffer %d != 14" % wp_saved["bld_workshop_26_23_smelt"].get("buffer_amount"))
			failures += 1
		if wp_saved["bld_workshop_26_23_craft"].get("buffer_amount") != 9:
			printerr("  [FAIL] Saved craft buffer %d != 9" % wp_saved["bld_workshop_26_23_craft"].get("buffer_amount"))
			failures += 1
		print("  [PASS] Serialized world state contains independent buffer amounts (Smelt: 14, Craft: 9).")

	# 3. Apply loaded state
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_state)
	if not apply_res.get("success", false):
		printerr("  [FAIL] apply_loaded_state_to_world failed!")
		failures += 1

	var restored_smelt: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_smelt")
	var restored_craft: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_craft")

	if restored_smelt == null or restored_smelt.buffer_amount != 14:
		printerr("  [FAIL] Restored smelt buffer is %s, expected 14!" % (restored_smelt.buffer_amount if restored_smelt else "null"))
		failures += 1
	if restored_craft == null or restored_craft.buffer_amount != 9:
		printerr("  [FAIL] Restored craft buffer is %s, expected 9!" % (restored_craft.buffer_amount if restored_craft else "null"))
		failures += 1

	var jobs_after_load := job_mgr.get_jobs_for_building("bld_workshop_26_23")
	if jobs_after_load.size() != 4:
		printerr("  [FAIL] Expected 4 jobs for workshop after load, got %d!" % jobs_after_load.size())
		failures += 1
	else:
		print("  [PASS] Exactly 4 workshop jobs reconstructed cleanly after load.")

	# 4. Anti-duplication on repeated load
	SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_state)
	var jobs_second_load := job_mgr.get_jobs_for_building("bld_workshop_26_23")
	if jobs_second_load.size() != 4:
		printerr("  [FAIL] Job duplication on second load! Count: %d, expected 4" % jobs_second_load.size())
		failures += 1
	else:
		print("  [PASS] Zero job duplication verified on repeated load.")

	# 5. Buffer overflow clamping
	var clamped_state = saved_state.duplicate(true)
	clamped_state["workplaces"]["bld_workshop_26_23_smelt"]["buffer_amount"] = 999
	SaveManagerScript.apply_loaded_state_to_world(world_instance, clamped_state)
	var clamped_smelt: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_workshop_26_23_smelt")
	if clamped_smelt.buffer_amount != 40:
		printerr("  [FAIL] Buffer overflow not clamped to capacity! Amount: %d, expected 40" % clamped_smelt.buffer_amount)
		failures += 1
	else:
		print("  [PASS] Buffer overflow safely clamped to capacity 40.")

	# 6. Backward compatibility with legacy save
	var legacy_state = saved_state.duplicate(true)
	legacy_state["workplaces"].erase("bld_workshop_26_23_smelt")
	legacy_state["workplaces"].erase("bld_workshop_26_23_craft")
	legacy_state["workplaces"]["bld_workshop_26_23"] = 15 # Legacy single-buffer integer format
	SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_state)
	var legacy_smelt = wp_mgr.get_workplace("bld_workshop_26_23_smelt")
	if legacy_smelt == null or legacy_smelt.buffer_amount != 15:
		printerr("  [FAIL] Backward compatibility with legacy workplace format failed!")
		failures += 1
	else:
		print("  [PASS] Backward compatibility verified: legacy single-buffer format restored to primary channel.")

	# 7. Backward compatibility with legacy nested dictionary format by parent building ID
	var nested_state = saved_state.duplicate(true)
	nested_state["workplaces"].erase("bld_workshop_26_23_smelt")
	nested_state["workplaces"].erase("bld_workshop_26_23_craft")
	nested_state["workplaces"]["bld_workshop_26_23"] = {
		"metal": 14,
		"tools": 9
	}
	SaveManagerScript.apply_loaded_state_to_world(world_instance, nested_state)
	var nested_smelt = wp_mgr.get_workplace("bld_workshop_26_23_smelt")
	var nested_craft = wp_mgr.get_workplace("bld_workshop_26_23_craft")

	if nested_smelt == null or nested_smelt.buffer_amount != 14:
		printerr("  [FAIL] Legacy nested save restoration: smelt buffer is %s, expected 14!" % (nested_smelt.buffer_amount if nested_smelt else "null"))
		failures += 1
	elif nested_craft == null or nested_craft.buffer_amount != 9:
		printerr("  [FAIL] Legacy nested save restoration: craft buffer is %s, expected 9!" % (nested_craft.buffer_amount if nested_craft else "null"))
		failures += 1
	else:
		print("  [PASS] Legacy nested dictionary format restored independently to both channels (Smelt: 14, Craft: 9).")

	# 7b. Independent clamping for legacy nested dictionary format
	var nested_clamp_state = saved_state.duplicate(true)
	nested_clamp_state["workplaces"].erase("bld_workshop_26_23_smelt")
	nested_clamp_state["workplaces"].erase("bld_workshop_26_23_craft")
	nested_clamp_state["workplaces"]["bld_workshop_26_23"] = {
		"metal": 888,
		"tools": 999
	}
	SaveManagerScript.apply_loaded_state_to_world(world_instance, nested_clamp_state)
	var clamped_nested_smelt = wp_mgr.get_workplace("bld_workshop_26_23_smelt")
	var clamped_nested_craft = wp_mgr.get_workplace("bld_workshop_26_23_craft")

	if clamped_nested_smelt == null or clamped_nested_smelt.buffer_amount != clamped_nested_smelt.buffer_capacity:
		printerr("  [FAIL] Legacy nested smelt overflow not clamped! Amount: %s, expected %d" % [(clamped_nested_smelt.buffer_amount if clamped_nested_smelt else "null"), (clamped_nested_smelt.buffer_capacity if clamped_nested_smelt else 40)])
		failures += 1
	elif clamped_nested_craft == null or clamped_nested_craft.buffer_amount != clamped_nested_craft.buffer_capacity:
		printerr("  [FAIL] Legacy nested craft overflow not clamped! Amount: %s, expected %d" % [(clamped_nested_craft.buffer_amount if clamped_nested_craft else "null"), (clamped_nested_craft.buffer_capacity if clamped_nested_craft else 40)])
		failures += 1
	else:
		print("  [PASS] Legacy nested dictionary buffer overflow clamped independently to channel capacities (Smelt: %d, Craft: %d)." % [clamped_nested_smelt.buffer_capacity, clamped_nested_craft.buffer_capacity])

	if failures == 0:
		print("  [PASS] TC-WS.6 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-WS.6 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-WS.7: Package Non-Regression Verification
# -----------------------------------------------------------------------------
func _test_tc_ws_7_non_regression() -> bool:
	print("--- Running TC-WS.7: Package Non-Regression Verification ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	# 1. Starter Farm & Woodcutter Camp buffers
	var farm_wp = wp_mgr.get_workplace("farm_starter")
	var wood_wp = wp_mgr.get_workplace("woodcutter_starter")

	if farm_wp == null or wood_wp == null:
		printerr("  [FAIL] Starter farm or woodcutter workplace missing!")
		failures += 1
	else:
		farm_wp.buffer_amount = 0
		wp_mgr.produce_to_buffer("farm_starter", 1.0)
		if farm_wp.buffer_amount <= 0:
			printerr("  [FAIL] Starter farm failed to produce to buffer!")
			failures += 1
		else:
			print("  [PASS] Starter farm produces food to buffer normally (%d)." % farm_wp.buffer_amount)

		wood_wp.buffer_amount = 0
		wp_mgr.produce_to_buffer("woodcutter_starter", 1.0)
		if wood_wp.buffer_amount <= 0:
			printerr("  [FAIL] Starter woodcutter failed to produce to buffer!")
			failures += 1
		else:
			print("  [PASS] Starter woodcutter produces wood to buffer normally (%d)." % wood_wp.buffer_amount)

	# 2. Watchtower blueprint and vision
	var wt_bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("watchtower", {})
	if wt_bp.get("vision_radius") != 15:
		printerr("  [FAIL] Watchtower vision radius is %s, expected 15!" % wt_bp.get("vision_radius"))
		failures += 1
	else:
		print("  [PASS] Watchtower blueprint intact.")

	# 3. Quarry & Mine blueprints
	var q_bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("quarry", {})
	var m_bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("mine", {})
	if q_bp.get("output_resource") != EconomyConfigScript.RES_STONE:
		printerr("  [FAIL] Quarry output_resource regressed!")
		failures += 1
	if m_bp.get("output_resource") != EconomyConfigScript.RES_ORE:
		printerr("  [FAIL] Mine output_resource regressed!")
		failures += 1
	print("  [PASS] Quarry and Mine blueprints intact.")

	# 4. Atomic cost reservation in ResourceManager
	var test_cost := {"wood": 10, "stone": 5}
	live_rm.add_resource("wood", 20)
	live_rm.add_resource("stone", 20)
	if not live_rm.reserve_cost(test_cost):
		printerr("  [FAIL] reserve_cost failed unexpectedly!")
		failures += 1
	else:
		live_rm.release_cost(test_cost)
		print("  [PASS] Atomic resource reservation and release operational.")

	if failures == 0:
		print("  [PASS] TC-WS.7 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-WS.7 had %d failures.\n" % failures)
		return false
