# KINGDOMS UNBOUND — Master Task Backlog

## Status Legend
- `[ ]` Not started
- `[-]` In progress
- `[x]` Completed and verified
- `[!]` Blocked

---

## Phase 0: Audit, Scaffold & Reproducibility (Current Phase)
- [x] **TASK-0.1:** Perform live MCP bridge status check and diagnose connection.
- [x] **TASK-0.2:** Isolate documentation folder via `docs/.gdignore` to prevent invalid asset import attempts.
- [x] **TASK-0.3:** Verify `MCPRuntime` autoload configuration in `project.godot`.
- [x] **TASK-0.4:** Author comprehensive documentation suite (`SCOPE_DECISIONS.md`, `GAME_RULES.md`, `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md`, `TEST_PLAN.md`, `BACKLOG.md`, `KNOWN_ISSUES.md`, `CHANGELOG.md`, `NIGHTLY_REPORT.md`).
- [ ] **TASK-0.5:** Run headless baseline validation command and record evidence in `TEST_PLAN.md` and `WORKLOG.md`.
- [ ] **TASK-0.6:** Git checkpoint Phase 0.

---

## Phase 1: Vertical Slice, World, Camera, Time & Visual-Validation Gate (Completed)
- [x] **TASK-1.1:** Create coordinate transformation utility script (`scripts/utils/iso_math.gd`) with forward/inverse 2:1 dimetric functions.
- [x] **TASK-1.2:** Write automated unit test `test_coordinates.gd` verifying all 13 reference coordinate cases.
- [x] **TASK-1.3:** Implement `TimeManager.gd` autoload supporting Pause (0×), 1×, 2×, 3× speeds, hourly/daily ticks.
- [x] **TASK-1.4:** Create procedural World Generator (`scripts/world/world_generator.gd`) generating 64×64 logical grid map from seed.
- [x] **TASK-1.5:** Implement 2:1 dimetric isometric diamond `TileMapLayer` presentation layer (`scenes/world/world_view.tscn`).
- [x] **TASK-1.6:** Implement interactive mouse hover tile highlight matching 32×16 diamond geometry.
- [x] **TASK-1.7:** Implement `CameraController.gd` with WASD/mouse pan, zoom, and map bounds clamping.
- [x] **TASK-1.8:** Create Starter Building instances (Town Hall 3×3, 4 Houses 2×2, Farm 2×2, Storehouse 2×2, Woodcutter Camp 2×2) with visible roofs and SW/SE facades.
- [x] **TASK-1.9:** Implement Main Menu (`scenes/ui/main_menu.tscn`) with New World (seed input, difficulty), Settings, Quit.
- [x] **TASK-1.10:** Implement in-game HUD with time controls, clock, resource summary bar, and pause menu.
- [x] **TASK-1.11:** Build and pass the mandatory **Visual-Validation Gate Scene** (`scenes/test/visual_validation_test.tscn`) verifying 32×16 diamond tiles, multi-tile building, props, moving citizen, and flawless Y-sorting.
- [x] **TASK-1.12:** Git checkpoint Phase 1.

---

## Phase 2: Authoritative Resources, Buildings & Economic Accounting (Completed)
- [x] **TASK-2.1:** Implement resource enum/constants and authoritative `ResourceManager.gd` autoload.
- [x] **TASK-2.2:** Define starter inventory quantities in `EconomyConfig` ($150$ food, $120$ wood, $60$ stone, $200$ gold, etc.).
- [x] **TASK-2.3:** Implement building definition resources (`BuildingData.gd`, costs, footprints, output buffers, capacities).
- [x] **TASK-2.4:** Implement building placement validation system (collision checks, terrain validity, resource deduction).
- [x] **TASK-2.5:** Implement atomic resource reservation system (`reserve_resource`, `commit_reservation`, `release_reservation`).
- [x] **TASK-2.6:** Implement Economy HUD showing storage capacity, available stock, reserved stock, and daily projections.
- [x] **TASK-2.7:** Write headless automated test for economy and building reservations.
- [x] **TASK-2.8:** Git checkpoint Phase 2.

---

## Phase 3: Citizens, Navigation & Real Jobs
- [ ] **TASK-3.1:** Implement `CitizenController.gd` and scene (`Citizen.tscn`) with foot pivot at $(12, 30)$ for Y-sorting.
- [ ] **TASK-3.2:** Spawn 24 citizens with unique stable IDs and starter job allocations (5 farmers, 4 woodcutters, 3 builders, 3 haulers, 9 idle).
- [ ] **TASK-3.3:** Implement grid A* pathfinding (`GridNavigation.gd`) on the 64×64 simulation grid.
- [ ] **TASK-3.4:** Implement citizen state machine (`Idle`, `Moving`, `Working`, `Hauling`, `Resting`, `SeekingFood`).
- [ ] **TASK-3.5:** Implement `JobManager.gd` with job lifecycle (`Available` $\to$ `Reserved` $\to$ `InProgress` $\to$ `Completed`/`Cancelled`).
- [ ] **TASK-3.6:** Implement citizen needs decay and hourly tick (Hunger, Fatigue, Health, Morale).
- [ ] **TASK-3.7:** Implement citizen inspection UI panel displaying active job, current path, and status reasons.
- [ ] **TASK-3.8:** Write headless unit tests for pathfinding, job claiming, and unreachability recovery.
- [ ] **TASK-3.9:** Git checkpoint Phase 3.

---

## Phase 4: Working Logistics Loop & Basic Automation
- [ ] **TASK-4.1:** Implement workplace output buffers and physical hauling jobs to Storehouse/Town Hall.
- [ ] **TASK-4.2:** Implement daily food consumption tick at midnight and seasonal farm output modifiers (Summer $1.2\times$, Winter $0.5\times$).
- [ ] **TASK-4.3:** Implement non-instant starvation escalation rules (Morale/Fatigue penalty $\to$ 5% Health drop/day).
- [ ] **TASK-4.4:** Implement configurable priority automation rules (e.g., Food critical $\to$ boost food hauling/harvesting).
- [ ] **TASK-4.5:** Implement rule execution budget to prevent infinite evaluation loops.
- [ ] **TASK-4.6:** Write automated test for logistics loop and automation rules.
- [ ] **TASK-4.7:** Git checkpoint Phase 4.

---

## Phase 5: Research, Exploration & Events
- [ ] **TASK-5.1:** Implement 4 research branches with 8–12 data-driven technologies.
- [ ] **TASK-5.2:** Implement Research Hall building and active project progress system.
- [ ] **TASK-5.3:** Implement Fog of War grid layer (Unexplored, Explored, Visible).
- [ ] **TASK-5.4:** Implement map Points of Interest with single-claim persistent discovery rewards.
- [ ] **TASK-5.5:** Implement random world events with cooldowns and UI notifications.
- [ ] **TASK-5.6:** Write automated test for research and POI rewards.
- [ ] **TASK-5.7:** Git checkpoint Phase 5.

---

## Phase 6: Factions, Diplomacy, Trade & Abstract Battles
- [ ] **TASK-6.1:** Implement 2 rival factions and 1 neutral faction with deterministic state.
- [ ] **TASK-6.2:** Implement scheduled merchant caravans and atomic trade exchange interface.
- [ ] **TASK-6.3:** Implement deterministic `BattleResolver.gd` factoring troops, equipment, fortifications, and terrain.
- [ ] **TASK-6.4:** Write automated test for trade conservation and battle resolutions.
- [ ] **TASK-6.5:** Git checkpoint Phase 6.

---

## Phase 7: Population Growth, Victory, Collapse & Summaries
- [ ] **TASK-7.1:** Implement deterministic immigration pacing (Housing, Food, Stability gating).
- [ ] **TASK-7.2:** Implement 5-day continuous prosperity victory hold condition.
- [ ] **TASK-7.3:** Implement deterministic collapse triggers (0 population, town hall destroyed for 3 days, 0% stability for 3 days).
- [ ] **TASK-7.4:** Implement World Summary screens for victory and collapse.
- [ ] **TASK-7.5:** Write automated test for victory timer reset and collapse rules.
- [ ] **TASK-7.6:** Git checkpoint Phase 7.

---

## Phase 8: Robust Save/Load & Persistence Hardening
- [ ] **TASK-8.1:** Implement versioned JSON serializer (`SaveLoadManager.gd`).
- [ ] **TASK-8.2:** Implement atomic file writes (`.tmp` $\to$ `.json`) and `.bak` backup preservation.
- [ ] **TASK-8.3:** Implement complete world deserialization and entity index reconstruction without node duplication.
- [ ] **TASK-8.4:** Implement corrupt save detection and error recovery UI.
- [ ] **TASK-8.5:** Write automated Save $\to$ Load $\to$ Save equivalence test.
- [ ] **TASK-8.6:** Git checkpoint Phase 8.

---

## Phase 9: Polish, Asset Integration, Balance & Release Candidate
- [ ] **TASK-9.1:** Integrate complete pixel-art asset set conforming to `docs/ASSET_STYLE_GUIDE.md` and 27-color palette.
- [ ] **TASK-9.2:** Add sound effects and ambient audio.
- [ ] **TASK-9.3:** Execute 100-citizen simulation stress test.
- [ ] **TASK-9.4:** Prepare release export configuration and manual smoke-test instructions.
- [ ] **TASK-9.5:** Final documentation synchronization and MVP acceptance signoff.
