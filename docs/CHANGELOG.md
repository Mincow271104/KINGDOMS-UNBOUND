# KINGDOMS UNBOUND — User-Visible Changelog

All notable changes to the Kingdoms Unbound project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### [0.7.0] - 2026-10-12
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
