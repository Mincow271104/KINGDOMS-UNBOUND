# KINGDOMS UNBOUND — User-Visible Changelog

All notable changes to the Kingdoms Unbound project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### [Package 1H] - 2026-10-18
#### Added
- Full builder construction lifecycle adhering strictly to GDD Section 7.3:
  - Player-placed buildings now start in `under_construction` state with `construction_progress = 0.0` and `construction_hours` defined per blueprint in `EconomyConfig.BLUEPRINTS`.
  - Immediate 100% footprint occupancy and atomic resource reservation/deduction upon site placement (fail-closed on null `ResourceManager`).
  - Dynamic builder jobs (`job.type == "builder"`) with concurrent worker capacity scaling by footprint (1x1: 2, 2x2: 3, 3x3: 4), bounded by walkable perimeter cells.
  - Real builder work loop in `CitizenController` advancing shared project progress by `delta_hours` per working builder; respects pause and time speed (1x, 2x, 3x).
  - Centralized idempotent completion transition (`complete_construction`) unlocking building operational features (workplace channels, guard posts, research UI, watchtower vision, housing capacity, storehouse capacity) and resetting amber scaffolding modulate.
  - Construction cancellation policy refunding 50% blueprint costs atomically, clearing footprint occupancy and visual node, and removing builder jobs.
  - Amber scaffolding visual modulate `Color(0.8, 0.7, 0.5, 0.7)` and dynamic HUD hover progress percentage `[Đang xây: X%]`.
  - Save/load persistence restoring exact construction progress and hours, zero duplicate jobs/nodes, zero deduction on reload, and legacy save compatibility.
  - Comprehensive automated test suite `scripts/test/test_construction.gd` covering TC-CON.1 through TC-CON.6 (PASS, Exit Code 0).
#### Changed / Hardened
- Strict construction completion threshold enforcement: `BuildingSystem.complete_building()` and `WorldView.complete_construction()` strictly refuse completion unless `state == "under_construction"`, `construction_hours > 0`, and `construction_progress >= construction_hours - 0.001`.
- Fail-closed progress delta validation: `advance_construction()` safely ignores negative or NaN/inf deltas without decrementing progress.
- Watchtower vision state filtering: `WorldView._on_simulation_hour_passed()` now only grants vision for watchtowers with `state == "active"`; paused, damaged, or under-construction towers do not grant vision.
- Job prefix collision immunity: `JobManager.job_matches_building()` enforces exact match or separator-aware prefix matching (`building_id + "_"`), preventing false-positive cancellation/cleanup collisions between neighboring buildings (e.g., `bld_house_28_28` vs `bld_house_28_280`).
- Safe cancellation refund storage guarantee: `BuildingSystem.cancel_construction()` performs all-or-nothing capacity validation before modifying world state, refusing cancellation if central storage cannot hold the full 50% refund.
- Save/load schema integrity: `SaveManager.validate_save_data()` validates building array types, blueprint names, coordinate bounds, positive finite hours, progress ranges, and valid state enums before world state deserialization begins.
- Idempotent construction job registration: `WorldView.register_construction_jobs()` verifies `state == "under_construction"`, preserves existing valid builder jobs on repeated calls up to concurrent worker capacity, handles stale jobs safely, and isolates overlapping textual prefix IDs.
- Blueprint footprint & integer validation: `SaveManager.validate_save_data()` strictly requires saved building footprints to match authoritative blueprints (rejecting mismatched sizes like 3x3 houses), requires grid coordinates and dimensions to be valid integers (rejecting fractional values), and gracefully handles legacy saves omitting size fields.
- Fail-closed storage effects on completion: `BuildingSystem.complete_building()` refuses activation if blueprint grants storage capacity but `ResourceManager` is missing, and guards against duplicate storage bonuses via `storage_applied`.
- Construction job perimeter validity & worker safety: In `WorldView.register_construction_jobs()`, enforced that retained builder jobs must have their `target_cell` contained in the building's computed perimeter, deduplicated jobs by `target_cell` while preserving active assignments (`IN_PROGRESS`/`RESERVED`), safely released displaced/cancelled workers to `IDLE` without leaving orphaned job references, and strictly capped retained and new jobs to `min(worker_capacity, valid_perimeter_cell_count)`. Added TC-CON.2 Subchecks A–D verifying stale cell cleanup, duplicate cell deduplication, worker safety, strict idempotency, and project isolation.
- Unrelated citizen assignment preservation & exact project ownership: In `WorldView._safe_cleanup_construction_job()`, only clear `active_job` and interrupt the worker when their `active_job` actually matches the job being removed, leaving citizens assigned to unrelated valid jobs completely undisturbed even if an invalid job's `worker_id` points to them. For citizens whose `active_job` is null but who are stranded in a job-related state, safely transition them to `IDLE` with cleared path. In `WorldView.register_construction_jobs()`, enforced strict project ownership (`j.type == "builder" and j.target_building_id == b_id`) to prevent cross-building job adoption or removal for projects with delimited prefixes (such as `bld_house_15_15_annex`). Added TC-CON.2 Subchecks E, F, G verifying assignment preservation, stale cleanup, and project isolation.

### [Package 1G] - 2026-10-18
#### Added
- Buildable Barracks (Doanh Trại) with 3x3 footprint, cost (25 Wood, 20 Stone, 5 Metal), and 2 guard capacity slots.
- Dedicated 96x80 pixel art sprite `assets/buildings/bld_barracks.png` conforming to 27-color fantasy palette with NW lighting.
- Active Barracks detection via `BuildingSystem.is_barracks_active(world_data)` strictly requiring `state == "active"`.
- Unique perimeter sentry cell calculation via `BuildingSystem.find_perimeter_cells(origin, size, world_data, max_count)`.
- Guard role gating at UI and controller levels:
  - Role dropdown item 7 disabled/annotated when no active Barracks exists.
  - Fail-closed role assignment preventing Guard assignment without an active Barracks.
  - Inactive Barracks duty release: guards pause duty with status "Cần Doanh Trại đang hoạt động" without losing their role.
- Deterministic guard duty loop in `CitizenController` with `State.GUARDING`, time pause safety, and urgent needs release (hunger >= 70, fatigue >= 85).
- Save/load persistence hardening attaching barracks checker to restored citizens, with zero node/job duplication.
- Comprehensive automated test suite `scripts/test/test_barracks.gd` covering TC-BR.1 through TC-BR.7 (PASS, Exit Code 0).

### [1.0.0-rc1] - 2026-10-12
#### Added
- Phase 9 Polish, Asset Integration, Stress Test & Release Candidate completed:
  - Procedural 16-bit audio synthesis subsystem `scripts/audio/audio_manager.gd` generating 8 crisp retro sound streams (UI click, building thud, error buzz, tech arpeggio chime, coin trade ding, victory fanfare, crisis alarm, and looping pastoral ambient music) with polyphonic playback pool and volume/mute controls.
  - 100-citizen simulation stress test `scripts/test/test_stress_100_citizens.gd` maintaining ~145 FPS at 1× and 3× speed (mean frame time 6.87 ms, beating the $\ge 60$ FPS threshold).
  - Extended multi-day simulation verified across 72 continuous simulation hours (3 game days) in 238.65 ms without stalls or memory leaks.
  - Windows Desktop release export presets configured in `export_presets.cfg`.
  - Comprehensive non-programmer manual verification guide in `docs/SMOKE_TEST_CHECKLIST.md`.
  - Full 12-suite regression test matrix passing 100% with Exit Code 0.
  - Verified visual fidelity adhering strictly to `docs/ASSET_STYLE_GUIDE.md` across Main Menu and 64×64 WorldView scenes.

### [0.9.0] - 2026-10-12
#### Added
- Phase 8 Robust Save/Load & Persistence Hardening completed:
  - `scripts/persistence/save_manager.gd`: versioned JSON schema (v1), atomic disk writes (`.tmp` → `.json`), `.bak` auto-backup on overwrite, schema/section validation, graceful corruption rejection, automatic `.bak` fallback recovery.
  - Full world state serialization: clock, resources (stock + capacities), buildings (id/type/cell/size/state/health), citizens (id/name/role/cell/stats), research progress, faction diplomatic states, POI claim states, victory/collapse progress, fog-of-war explored cells.
  - Zero-duplication reconstruction in `apply_loaded_state_to_world()`: clears old scene nodes before restoring from save data.
  - In-Game Pause Menu: "💾 Lưu Thế Giới" and "📂 Tải Bản Lưu" buttons with success/error status feedback label.
  - Main Menu: "📂 Tải Thế Giới" button dynamically enabled if `user://saves/world_save.json` or `.bak` exists.
  - Daily autosave: configurable interval (default: every 1 game day) with EventManager notification.
  - Automated test suite `scripts/test/test_save_load.gd` (TC-8.1, TC-8.2, TC-8.3 all passed):
    - TC-8.1: save→load→save canonical equivalence (24 citizens, 8 buildings, fog-of-war 100% preserved).
    - TC-8.2: corrupt/incompatible save rejection; automatic .bak fallback verified.
    - TC-8.3: HUD save button UI workflow and MainMenu load button UI verified end-to-end.

### [0.8.0] - 2026-10-12
#### Added
- Phase 7 Population Growth, Victory, Collapse & Summaries completed:
  - Deterministic immigration manager `scripts/economy/immigration_manager.gd` pacing arrivals (every 3 days at 06:00) with condition gating (housing capacity $>$ population, food $\ge 30$, stability $\ge 50\%$, morale $\ge 60\%$), generating unique citizen IDs and Vietnamese names.
  - Authoritative victory, crisis, and collapse manager `scripts/core/victory_manager.gd` enforcing continuous 5-day (120-hour) prosperity hold (population $\ge 30$, food $\ge 500$, treasury $\ge 1000$, stability $\ge 80\%$, morale $\ge 75\%$, technologies $\ge 3$) with immediate duration reset to 0 upon metric lapse.
  - Deterministic collapse failure triggers: Extinction (population $\le 0$), Town Hall Ruin ($> 72$ hours destroyed), and Prolonged Anarchy ($> 72$ hours at $0\%$ stability) generating structured failure summaries without deleting save data.
  - Legacy achievement reward system with double-spend protection (`claim_legacy_reward`).
  - In-Game HUD Victory modal dialog ("👑 CHIẾN THẮNG THỊNH VƯỢNG!"), Collapse modal dialog ("💀 VƯƠNG QUỐC SỤP ĐỔ!"), Crisis alert banner, and dynamic population display (`👥 Dân số: %d/%d`).
  - Automated headless test suite `scripts/test/test_victory_and_collapse.gd` (TC-7.1, TC-7.2, TC-7.3 passed).

#### Added
- Phase 6 Factions, Diplomacy, Trade & Abstract Battles completed:
  - Faction management subsystem `scripts/factions/faction_data.gd` and `scripts/factions/faction_manager.gd` tracking 2 rival kingdoms ("Cổ Thành Thiết Giáp", "Thương Hội Vân Đồn") and 1 neutral tribe ("Bản Làng Rừng Xanh") with continuous disposition (-100 to +100), stability, military power, treaties (Neutral, Peace, Non-Aggression, Alliance, War), diplomatic gift sending, and neutral tribe ascension mechanics.
  - Royal Trade Caravan simulation `scripts/trade/trade_caravan.gd` with deterministic seed arrivals (every 5 days), finite inventories, asymmetric buy/sell pricing (with diplomatic disposition discounts), atomic item transactions, and double-spending prevention.
  - Deterministic Battle Resolver `scripts/combat/battle_resolver.gd` modeling attacker/defender troops, equipment tier (1-3), morale, fortification level (0-3), terrain bonuses (chokepoints, high ground), casualty calculation, and plunder spoils (20% defender stock) satisfying GDD 10.4 without random outcome swings.
  - In-Game HUD Royal Diplomacy & Trade interface (`scenes/ui/hud.tscn` and `scripts/ui/hud.gd`) accessible via HUD button and shortcut `KEY_Y`.
  - Automated headless test suite `scripts/test/test_factions_and_battles.gd` (TC-6.1 and TC-6.2 passed).

#### Added
- Phase 5 Research, Exploration & Events completed:
  - Central technology tree `scripts/research/tech_tree.gd` with 4 branches (survival, production, military, mysticism) and 10 technologies with prerequisites and atomic resource deductions.
  - Royal Research Institute system `scripts/research/research_manager.gd` enforcing single active project constraint, atomic upfront cost deduction, 50% cancellation refund, pause safety, and global research bonuses (+500 storage capacity, +25% research speed).
  - 3-state Fog of War simulation `scripts/world/fog_of_war.gd` (UNEXPLORED, EXPLORED, VISIBLE) with diamond sight reveals.
  - Deterministic Points of Interest `scripts/world/poi_manager.gd` (Ancient Ruins, Abandoned Mines, Sacred Groves, Ancient Shrines) with single-claim persistent discovery rewards rejecting double-spending.
  - World events system `scripts/core/world_event_system.gd` with periodic positive/negative events and cooldown intervals.
  - Decoupled event router autoload `scripts/core/event_manager.gd` registered in `project.godot`.
  - In-Game HUD Royal Research Institute panel (`KEY_T`), Research button, and Event Banner.
  - Ancient Ruins pixel art prop `assets/props/prop_poi_ruins.png`.
  - Automated test suite `scripts/test/test_research_and_exploration.gd` (TC-5.1, TC-5.2, TC-5.3 passed).

### [0.5.0] - 2026-10-12
#### Added
- Phase 4 Working Logistics Loop & Basic Automation completed:
  - Local workplace output buffers `scripts/economy/workplace_manager.gd` (Farm: 50 food buffer, Woodcutter: 40 wood buffer) preventing instant teleportation of goods.
  - Physical hauling loop: haulers claim hauling jobs, travel to workplace access points, extract cargo, navigate to storehouses, and deposit goods into central stock.
  - Seasonal agriculture output modifiers ($1.2\times$ Summer, $0.5\times$ Winter, $1.0\times$ Spring/Autumn) scaling farm production.
  - Non-instant starvation escalation: when food depletes, "Nạn đói" state initiates; health decays gradually at 5%/day with 0 instant deaths, recovering naturally when fed.
  - Configurable priority automation rules with strict execution budget ($O(1)$ constant time) in `scripts/economy/automation_manager.gd` preventing performance death spirals.
  - In-game HUD citizen inspector displays live carried cargo.
  - Automated headless test suite `scripts/test/test_logistics.gd` (TC-4.1, TC-4.2, TC-4.3 passed).

### [0.4.0] - 2026-10-12
#### Added
- Phase 3 Citizens, Navigation & Real Jobs completed:
  - Discrete 2D A* grid pathfinder `scripts/navigation/grid_navigation.gd` operating on 64×64 simulation grid with obstacle avoidance.
  - Authoritative Job Manager `scripts/jobs/job_manager.gd` tracking workplace capacities and construction/production job lifecycles.
  - Citizen controller `scripts/entities/citizen_controller.gd` and scene `scenes/entities/citizen.tscn` with ground-contact foot pivot at (12, 30) for Y-sorting.
  - Instantiation of exactly 24 starter citizens with unique stable IDs and starter roles (5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle).
  - Hourly citizen need decay simulation (Hunger, Fatigue, Health, Morale).
  - Citizen inspection UI panel integrated into HUD (`scenes/ui/hud.tscn` and `scripts/ui/hud.gd`) displaying citizen stats, state, job, and path.
  - Automated headless test suite `scripts/test/test_citizens.gd` (TC-3.1 and TC-3.2 passed).

### [0.3.0] - 2026-10-12
#### Added
- Phase 2 Authoritative Economy & Building Systems completed:
  - Central data-driven economy configuration `scripts/economy/economy_config.gd` with 9 stable resource IDs and building blueprints.
  - Authoritative `scripts/economy/resource_manager.gd` singleton with atomic multi-resource cost reservation (`reserve_cost`), deduction (`commit_cost`), and cancellation (`release_cost`).
  - Storage capacity limits enforcement and daily food upkeep consumption tick ($0.8 \times 24 = 19.2 \approx 20$ Food/day).
  - Building placement validation `scripts/economy/building_system.gd` enforcing grid bounds, water prohibition, and occupancy tracking.
  - Interactive In-Game Build Menu and real-time ghost building placement preview.
  - Automated headless economy test suite `scripts/test/test_economy.gd` (TC-2.1 and TC-2.2 passed).
#### Added
- Phase 1 Vertical Slice & Visual-Validation Gate completed:
  - Coordinate decoupling utility `scripts/utils/iso_math.gd` with 2:1 dimetric isometric forward/inverse math.
  - Automated coordinate unit test `scripts/test/test_coordinates.gd` (TC-1.1 passed).
  - Authoritative simulation clock `scripts/core/time_manager.gd` with pause safety, speeds (0x–3x), and calendar.
  - Automated TimeManager unit test `scripts/test/test_time_manager.gd` (TC-1.4 passed).
  - Procedural pixel-art asset generator `scripts/tools/generate_pixel_assets.gd` generating 13 assets adhering strictly to `docs/ASSET_STYLE_GUIDE.md` and 27-color palette.
  - Deterministic procedural world generator `scripts/world/world_generator.gd` generating 64×64 simulation grid.
  - Automated world generator reproducibility test `scripts/test/test_world_gen.gd` (TC-1.2 passed).
  - Dedicated Visual-Validation Gate scene `scenes/test/visual_validation_test.tscn` demonstrating terrain, props, building with visible rooftop/facade, moving citizen, diamond cursor hover, and flawless Y-sorting.
  - In-Game HUD `scenes/ui/hud.tscn` with time controls, clock, resource ledger, and pause menu.
  - 64×64 Full World View `scenes/world/world_view.tscn` with starter buildings and 24 citizens.
  - Main Menu `scenes/ui/main_menu.tscn` with New World (seed, difficulty), Settings, and Quit.
  - Configured `run/main_scene` in `project.godot`.
#### Added
- Formalized comprehensive project specification suite:
  - `docs/SCOPE_DECISIONS.md` resolving all GDD design ambiguities and starter resource allocations.
  - `docs/GAME_RULES.md` specifying 2:1 dimetric isometric coordinate formulas, simulation tick schedules, needs decay rates, and victory/collapse conditions.
  - `docs/ARCHITECTURE.md` establishing strict separation between 64×64 logical simulation and presentation layers.
  - `docs/IMPLEMENTATION_PLAN.md` defining phased execution roadmap across 10 technical phases.
  - `docs/TEST_PLAN.md` establishing headless command-line and Godot MCP verification suites.
  - `docs/BACKLOG.md` detailing prioritized tasks and dependency chains.
  - `docs/KNOWN_ISSUES.md` recording technical diagnostic solutions.
- Added `docs/.gdignore` to cleanly isolate documentation from Godot's asset importer.
- Configured `MCPRuntime` autoload singleton in `project.godot`.
- Verified live Godot MCP bridge connection on port 6505.
