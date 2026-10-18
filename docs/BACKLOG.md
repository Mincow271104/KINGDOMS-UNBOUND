# KINGDOMS UNBOUND â€” Master Task Backlog

## Status Legend
- `[ ]` Not started
- `[-]` In progress
- `[x]` Completed and verified
- `[!]` Blocked

---

## Phase 0: Audit, Scaffold & Reproducibility (Completed)
- [x] **TASK-0.1:** Perform live MCP bridge status check and diagnose connection.
- [x] **TASK-0.2:** Isolate documentation folder via `docs/.gdignore` to prevent invalid asset import attempts.
- [x] **TASK-0.3:** Verify `MCPRuntime` autoload configuration in `project.godot`.
- [x] **TASK-0.4:** Author comprehensive documentation suite (`SCOPE_DECISIONS.md`, `GAME_RULES.md`, `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md`, `TEST_PLAN.md`, `BACKLOG.md`, `KNOWN_ISSUES.md`, `CHANGELOG.md`, `NIGHTLY_REPORT.md`).
- [x] **TASK-0.5:** Run headless baseline validation command and record evidence in `TEST_PLAN.md` and `WORKLOG.md`.
- [x] **TASK-0.6:** Git checkpoint Phase 0.

---

## Phase 1: Vertical Slice, World, Camera, Time & Visual-Validation Gate (Completed)
- [x] **TASK-1.1:** Create coordinate transformation utility script (`scripts/utils/iso_math.gd`) with forward/inverse 2:1 dimetric functions.
- [x] **TASK-1.2:** Write automated unit test `test_coordinates.gd` verifying all 13 reference coordinate cases.
- [x] **TASK-1.3:** Implement `TimeManager.gd` autoload supporting Pause (0Ã—), 1Ã—, 2Ã—, 3Ã— speeds, hourly/daily ticks.
- [x] **TASK-1.4:** Create procedural World Generator (`scripts/world/world_generator.gd`) generating 64Ã—64 logical grid map from seed.
- [x] **TASK-1.5:** Implement 2:1 dimetric isometric diamond `TileMapLayer` presentation layer (`scenes/world/world_view.tscn`).
- [x] **TASK-1.6:** Implement interactive mouse hover tile highlight matching 32Ã—16 diamond geometry.
- [x] **TASK-1.7:** Implement `CameraController.gd` with WASD/mouse pan, zoom, and map bounds clamping.
- [x] **TASK-1.8:** Create Starter Building instances (Town Hall 3Ã—3, 4 Houses 2Ã—2, Farm 2Ã—2, Storehouse 2Ã—2, Woodcutter Camp 2Ã—2) with visible roofs and SW/SE facades.
- [x] **TASK-1.9:** Implement Main Menu (`scenes/ui/main_menu.tscn`) with New World (seed input, difficulty), Settings, Quit.
- [x] **TASK-1.10:** Implement in-game HUD with time controls, clock, resource summary bar, and pause menu.
- [x] **TASK-1.11:** Build and pass the mandatory **Visual-Validation Gate Scene** (`scenes/test/visual_validation_test.tscn`) verifying 32Ã—16 diamond tiles, multi-tile building, props, moving citizen, and flawless Y-sorting.
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

## Phase 3: Citizens, Navigation & Real Jobs (Completed)
- [x] **TASK-3.1:** Implement `CitizenController.gd` and scene (`Citizen.tscn`) with foot pivot at $(12, 30)$ for Y-sorting.
- [x] **TASK-3.2:** Spawn 24 citizens with unique stable IDs and starter job allocations (5 farmers, 4 woodcutters, 3 builders, 3 haulers, 9 idle).
- [x] **TASK-3.3:** Implement grid A* pathfinding (`GridNavigation.gd`) on the 64Ã—64 simulation grid.
- [x] **TASK-3.4:** Implement citizen state machine (`Idle`, `Moving`, `Working`, `Hauling`, `Resting`, `SeekingFood`).
- [x] **TASK-3.5:** Implement `JobManager.gd` with job lifecycle (`Available` $\to$ `Reserved` $\to$ `InProgress` $\to$ `Completed`/`Cancelled`).
- [x] **TASK-3.6:** Implement citizen needs decay and hourly tick (Hunger, Fatigue, Health, Morale).
- [x] **TASK-3.7:** Implement citizen inspection UI panel displaying active job, current path, and status reasons.
- [x] **TASK-3.8:** Write headless unit tests for pathfinding, job claiming, and unreachability recovery.
- [x] **TASK-3.9:** Git checkpoint Phase 3.

---

## Phase 4: Working Logistics Loop & Basic Automation (Completed)
- [x] **TASK-4.1:** Implement workplace output buffers and physical hauling jobs to Storehouse/Town Hall.
- [x] **TASK-4.2:** Implement daily food consumption tick at midnight and seasonal farm output modifiers (Summer $1.2\times$, Winter $0.5\times$).
- [x] **TASK-4.3:** Implement non-instant starvation escalation rules (Morale/Fatigue penalty $\to$ 5% Health drop/day).
- [x] **TASK-4.4:** Implement configurable priority automation rules (e.g., Food critical $\to$ boost food hauling/harvesting).
- [x] **TASK-4.5:** Implement rule execution budget to prevent infinite evaluation loops.
- [x] **TASK-4.6:** Write automated test for logistics loop and automation rules.
- [x] **TASK-4.7:** Git checkpoint Phase 4.

---

## Phase 5: Research, Exploration & Events (Completed)
- [x] **TASK-5.1:** Implement 4 research branches with 8â€“12 data-driven technologies (`scripts/research/tech_tree.gd`).
- [x] **TASK-5.2:** Implement Royal Research Institute system and active single-project progress (`scripts/research/research_manager.gd`).
- [x] **TASK-5.3:** Implement Fog of War grid layer (Unexplored, Explored, Visible) (`scripts/world/fog_of_war.gd`).
- [x] **TASK-5.4:** Implement map Points of Interest with single-claim persistent discovery rewards (`scripts/world/poi_manager.gd`).
- [x] **TASK-5.5:** Implement world events with deterministic cooldowns and UI notifications (`scripts/core/world_event_system.gd`).
- [x] **TASK-5.6:** Write automated tests for research, Fog of War, and POI rewards (`scripts/test/test_research_and_exploration.gd`).
- [x] **TASK-5.7:** Git checkpoint Phase 5.

---

## Phase 6: Factions, Diplomacy, Trade & Abstract Battles (Completed)
- [x] **TASK-6.1:** Implement 2 rival factions and 1 neutral faction with deterministic state (`scripts/factions/faction_manager.gd`, `faction_data.gd`).
- [x] **TASK-6.2:** Implement scheduled merchant caravans and atomic trade exchange interface (`scripts/trade/trade_caravan.gd`).
- [x] **TASK-6.3:** Implement deterministic `BattleResolver.gd` factoring troops, equipment, fortifications, and terrain.
- [x] **TASK-6.4:** Write automated test for trade conservation and battle resolutions (`scripts/test/test_factions_and_battles.gd`).
- [x] **TASK-6.5:** Git checkpoint Phase 6.

---

## Phase 7: Population Growth, Victory, Collapse & Summaries (Completed)
- [x] **TASK-7.1:** Implement deterministic immigration pacing (Housing, Food, Stability gating) (`scripts/economy/immigration_manager.gd`).
- [x] **TASK-7.2:** Implement 5-day continuous prosperity victory hold condition (`scripts/core/victory_manager.gd`).
- [x] **TASK-7.3:** Implement deterministic collapse triggers (0 population, town hall destroyed for 3 days, 0% stability for 3 days).
- [x] **TASK-7.4:** Implement World Summary screens for victory and collapse (`scenes/ui/hud.tscn`, `scripts/ui/hud.gd`).
- [x] **TASK-7.5:** Write automated test for victory timer reset and collapse rules (`scripts/test/test_victory_and_collapse.gd`).
- [x] **TASK-7.6:** Git checkpoint Phase 7.

---

## Phase 8: Robust Save/Load & Persistence Hardening (Completed)
- [x] **TASK-8.1:** Implement versioned JSON serializer (`SaveManager.gd`).
- [x] **TASK-8.2:** Implement atomic file writes (`.tmp` $\to$ `.json`) and `.bak` backup preservation.
- [x] **TASK-8.3:** Implement complete world deserialization and entity index reconstruction without node duplication.
- [x] **TASK-8.4:** Implement corrupt save detection, schema validation, and error recovery UI.
- [x] **TASK-8.5:** Write automated Save $\to$ Load $\to$ Save equivalence test suite (`scripts/test/test_save_load.gd`).
- [x] **TASK-8.6:** Git checkpoint Phase 8.

---

## Phase 9: Polish, Asset Integration, Balance & Release Candidate (Completed)
- [x] **TASK-9.1:** Integrate complete pixel-art asset set conforming to `docs/ASSET_STYLE_GUIDE.md` and 27-color palette.
- [x] **TASK-9.2:** Add procedural sound effects and looping ambient music (`scripts/audio/audio_manager.gd`).
- [x] **TASK-9.3:** Execute 100-citizen simulation stress test (`test_stress_100_citizens.gd`, TC-9.1 PASS at ~145 FPS).
- [x] **TASK-9.4:** Prepare release export configuration (`export_presets.cfg`) and manual smoke-test instructions (`docs/SMOKE_TEST_CHECKLIST.md`).
- [x] **TASK-9.5:** Final documentation synchronization and MVP acceptance signoff.

---

## Package 1G: Barracks & Guard Integration (Completed)
- [x] **TASK-1G.1:** Authoritative blueprint `barracks` (3x3 footprint, 25 Wood, 20 Stone, 5 Metal, 2 guard capacity, job_type "guard").
- [x] **TASK-1G.2:** Active state detection `BuildingSystem.is_barracks_active(world_data)` and perimeter sentry cell resolution `find_perimeter_cells`.
- [x] **TASK-1G.3:** Custom 27-color fantasy palette pixel-art sprite `bld_barracks.png` (96x80 px) with fortified walls, gateway arch, crest, and watchtower.
- [x] **TASK-1G.4:** CitizenController guard duty state machine (`State.GUARDING`), fail-closed role gating, needs release, time pause safety, and reason updates.
- [x] **TASK-1G.5:** HUD integration with `BarracksBtn`, role option 7 ("Vá»‡ Binh (Guard)"), dynamic annotation/disabling when inactive, and selection error audio feedback.
- [x] **TASK-1G.6:** WorldView lifecycle integration, guard job registration, save/load workplace sync, and citizen checker attachment.
- [x] **TASK-1G.7:** Save/Load persistence hardening attaching barracks checker to restored citizens, with zero node/job duplication.
- [x] **TASK-1G.8:** Automated test suite `scripts/test/test_barracks.gd` covering TC-BR.1 through TC-BR.7 (PASS, Exit Code 0).
- [x] **TASK-1G.9:** Package 1G Review Fix â€” Multi-barracks specific building ID tracking, unique guard positions deduplication, work-related need decay in State.GUARDING, genuine TimeManager pause verification, and comprehensive regression test suite (PASS, Exit Code 0).

---

## Package 1H: Builder & Construction Lifecycle (Completed)
- [x] **TASK-1H.1:** Construction Site Placement & State Machine (`under_construction`, `construction_progress = 0.0`, `construction_hours` from blueprints, immediate full footprint occupancy).
- [x] **TASK-1H.2:** Cost reservation & atomic deduction on placement, fail-closed on null `ResourceManager` or insufficient funds.
- [x] **TASK-1H.3:** Dynamic builder job generation (`job.type == "builder"`) with concurrent worker capacities (1x1: 2, 2x2: 3, 3x3: 4) bounded by walkable perimeter cells.
- [x] **TASK-1H.4:** Real builder work loop in `CitizenController` advancing shared building progress by `delta_hours` per active working builder, respecting time pause and speeds (1x, 2x, 3x).
- [x] **TASK-1H.5:** Centralized idempotent completion transition (`complete_construction`) unlocking building operations (workplaces, guard jobs, research UI, watchtower vision, housing, storehouse capacity) and resetting visual scaffolding modulate.
- [x] **TASK-1H.6:** Cancellation policy refunding 50% blueprint costs atomically, releasing occupancy, removing jobs, and freeing visual nodes idempotently.
- [x] **TASK-1H.7:** Visual scaffolding amber modulate `Color(0.8, 0.7, 0.5, 0.7)` and dynamic HUD hover progress percentage `[Äang xÃ¢y: X%]`.
- [x] **TASK-1H.8:** Save/Load persistence preserving construction progress and hours, zero duplicate jobs/nodes, zero deduction on reload, and legacy save compatibility.
- [x] **TASK-1H.9:** Automated test suite `scripts/test/test_construction.gd` covering TC-CON.1 through TC-CON.6 (PASS, Exit Code 0).
- [x] **TASK-1H.10:** Package 1H Final Hardening — Strict construction completion threshold enforcement (`construction_progress >= construction_hours - 0.001`), fail-closed negative/NaN progress delta rejection, watchtower vision state filtering (`state == "active"`), separator-aware job prefix matching (`job_matches_building`), all-or-nothing cancellation refund storage capacity verification, save/load schema validation against corrupted/out-of-bounds building records, and genuine TimeManager pause verification (PASS, Exit Code 0).
- [x] **TASK-1H.11:** Package 1H Final Review Fix — Idempotent construction job registration (preventing duplicate jobs on repeated calls, preserving capacity and perimeter bounds, isolating overlapping text prefix IDs), blueprint footprint enforcement in SaveManager.validate_save_data (rejecting mismatched footprints and fractional coordinates/dimensions, handling legacy saves without size fields), strengthened watchtower hourly tick regression testing (under-construction state unrevealed through _on_simulation_hour_passed), fail-closed completion when required storage effects cannot be applied (missing ResourceManager), and non-duplicating storage bonus (PASS, Exit Code 0).
- [x] **TASK-1H.12:** Package 1H Final Fix #2 — Construction job perimeter validity and deduplication in WorldView.register_construction_jobs (checking actual perimeter containment, eliminating duplicate target cells while preserving active worker assignments, safely releasing displaced workers to IDLE without leaving orphaned job references, capping to min(worker_capacity, valid_perimeter_cell_count), strict idempotency, and project isolation across overlapping textual prefix IDs) (PASS, Exit Code 0).
- [x] **TASK-1H.13:** Package 1H Final Fix #3 — Preserve unrelated valid citizen assignments during construction cleanup in WorldView._safe_cleanup_construction_job (matching active_job strictly rather than matching worker_id alone, preserving unrelated jobs and working states, releasing stranded citizens without active_job to IDLE), exact project ownership in register_construction_jobs (preventing adoption or removal of builder jobs belonging to other projects sharing delimited prefixes like bld_house_15_15_annex), and regression tests covering Subchecks E, F, G in test_construction.gd (PASS, Exit Code 0).

---

## Package 1I: Palisade & Fortification System (Completed)
- [x] **TASK-1I.1:** Authoritative blueprint `palisade` in `EconomyConfig` (1x1 footprint, 4 Wood, 2 Stone, 3.0h construction time, 0 workers, empty storage, no production jobs).
- [x] **TASK-1I.2:** Pixel-art asset `assets/buildings/bld_palisade.png` (32x36 px) conforming to 27-color fantasy palette, NW lighting, and 2:1 dimetric perspective.
- [x] **TASK-1I.3:** WorldView visual rendering integration (texture loading, sprite offset `Vector2(-16.0, -28.0)`, Vietnamese display name `"Tường Rào Phòng Ngự (1x1)"`).
- [x] **TASK-1I.4:** Full construction lifecycle integration (initial state `under_construction`, worker capacity 2, amber modulate scaffolding, idempotent completion transition resetting modulate, 50% refund cancellation crediting 2W+1S atomically with storage validation and occupancy cleanup).
- [x] **TASK-1I.5:** Navigation grid obstacle integration (`GridNavigation` recognizes palisade cells as solid obstacles, `is_cell_walkable == false`, pathfinding routes around).
- [x] **TASK-1I.6:** Settlement fortification integration (`BuildingSystem.calculate_fortification_level` and `BattleResolver.calculate_settlement_fortification_level` deduplicating active palisades and mapping to levels 0..3 with battle combat bonuses).
- [x] **TASK-1I.7:** HUD Build Menu integration (`PalisadeBtn` wired to `_select_building("palisade")`, ghost preview with correct dimensions/offsets).
- [x] **TASK-1I.8:** Save/Load persistence & regression test suite `scripts/test/test_palisade.gd` covering TC-PA.1 through TC-PA.7 (PASS, Exit Code 0).
- [x] **TASK-1I.9:** Package 1I Final UI Fix — Adjusted `BuildMenuPanel` geometry in `scenes/ui/hud.tscn` (`offset_top = -466.0`, `offset_bottom = -56.0`, height 410 px; `offset_left = -340.0`, `offset_right = 340.0`, width 680 px) ensuring all 6 rows (11 buttons) and `CloseBuildBtn` are fully enclosed without clipping, maintaining 8 px clearance above `BottomBar`, and verified via automated layout geometry subchecks in `test_palisade.gd` TC-PA.7 (PASS, Exit Code 0).

---

## Package 1J: Settlement Battle & Fortification Integration (Completed)
- [x] **TASK-1J.1:** Authoritative settlement battle API `BattleResolver.resolve_settlement_battle(attacker_force, defender_force, defender_world_data, seed_val) -> BattleReport` connecting deterministic battle resolution directly to `WorldGenerator.WorldData`.
- [x] **TASK-1J.2:** Dynamic settlement fortification calculation via `BuildingSystem.calculate_fortification_level(defender_world_data)`, overriding/enforcing authoritative fortification levels (0..3) on defender forces and failing closed (level 0, bonus 1.0) on null or invalid settlement data.
- [x] **TASK-1J.3:** Deep-clone caller input protection (`attacker_force.duplicate(true)`, `defender_force.duplicate(true)`) guaranteeing zero side effects or mutation on caller dictionaries, and enriching `BattleReport.details` with `"fortification_level"`, `"fortification_bonus"`, and `"has_settlement_context"` while maintaining backward compatibility with direct `resolve_battle()`.
- [x] **TASK-1J.4:** Automated test suite `scripts/test/test_battle_fortification.gd` covering all 12 test conditions (TC-BF.1 through TC-BF.12) with 100% pass rate.
- [ ] **FUTURE-BATTLE-1:** Implement live production battle trigger and troop deployment flow (deferred to future combat milestone per project scope).
