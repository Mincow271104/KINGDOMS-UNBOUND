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
- [x] **FUTURE-BATTLE-1:** Implement live production battle trigger and troop deployment flow (Completed via Package 1K Settlement Defense Raid Loop).

---

## Package 1K: Live War & Settlement Defense Battle Loop (Completed)
- [x] **TASK-1K.1:** Dedicated `BattleCampaignManager` (`scripts/combat/battle_campaign_manager.gd`) managing raid scheduling (3-day initial delay, 5-day recurring delay), eligibility checks, deterministic seed generation, and repeat execution immunity.
- [x] **TASK-1K.2:** Authoritative force modeling: attacking troops derived from `FactionData.military_power` (1..20 troops), type equipment tier, and stability morale; defending troops derived from living Guards gated by active Barracks and available resource stock.
- [x] **TASK-1K.3:** Zero-troop edge case handling and casualty bounding in `BattleResolver.resolve_battle()` (unopposed raids, 0 vs 0, and casualties strictly clamped $\le$ troops).
- [x] **TASK-1K.4:** Exactly-once result application: deterministic guard casualties with clean job/lifecycle removal, attacker military power reduction without negative values, and resource plunder respecting available stock.
- [x] **TASK-1K.5:** Player feedback integration in HUD and Diplomacy panel: expected raid warnings, battle result banners with casualty and fortification breakdowns, peace cancellation notices, and unopposed raid reporting.
- [x] **TASK-1K.6:** Save/load persistence in `SaveManager` (`"battle_campaign"` section) supporting roundtrip preservation, replay immunity, and legacy save compatibility.
- [x] **TASK-1K.7:** Automated test suite `scripts/test/test_live_battle_loop.gd` covering TC-LB.1 through TC-LB.14 (PASS, Exit Code 0).

---

## Package 1P: Emerging Faction Ascension Gates (Completed)
- [x] **TASK-1P.1:** Authoritative ascension gates (`ASCENSION_MIN_DAY = 10`, `ASCENSION_MIN_POPULATION = 45`, `ASCENSION_MIN_WOOD = 60`, `ASCENSION_MIN_HERBS = 30`, `ASCENSION_MIN_STABILITY = 50.0`) and single emerging power check (`has_emerging_power()`, `can_emerging_faction_ascend(day)`).
- [x] **TASK-1P.2:** Non-consumptive ascension evolution to `emerging_power` (`Liên Minh Rừng Thiêng`), `SaveManager` faction resource persistence, HUD event announcement, and automated test suite `scripts/test/test_emerging_faction_ascension.gd` (PASS, Exit Code 0).

---

## Package 1Q: Faction Strategic Profiles & Existence Status (Completed)
- [x] **TASK-1Q.1:** Canonical `strategic_goal` and `existence_status` fields on `FactionData` with Vietnamese localization helpers (`get_strategic_goal_label`, `get_existence_status_label`), ascension goal transition to `consolidate_power`, fail-closed `SaveManager` validation, HUD diplomacy card rendering, and automated test suite `scripts/test/test_faction_profiles.gd` (PASS, Exit Code 0).

---

## Package 1R: Deterministic Faction Strategic Decision Engine (Completed)
- [x] **TASK-1R.1:** Pure side-effect-free `FactionStrategyPlanner` (`scripts/factions/faction_strategy_planner.gd`) translating active faction goals into canonical intents (`military_buildup`, `trade_expansion`, `community_development`, `power_consolidation`), `FactionManager` daily evaluation signal `strategic_intent_evaluated`, status/crisis hardening (`MISS-01`, `MISS-02`), and automated test suite `scripts/test/test_faction_strategy_planner.gd` (PASS, Exit Code 0).

---

## Package 1S: Faction Strategic Intent Execution (Completed)
- [x] **TASK-1S.1:** Dedicated `FactionStrategyExecutor` (`scripts/factions/faction_strategy_executor.gd`) executing bounded, deterministic, atomic actions for `military_buildup`, `trade_expansion`, `community_development`, and `power_consolidation` with explicit resource costs, ceilings, and reason codes while keeping `FactionStrategyPlanner` 100% pure.
- [x] **TASK-1S.2:** `FactionManager` daily execution integration (`execute_faction_strategic_intent`, `strategic_intent_executed` signal, sorted deterministic faction order, same-day idempotency, and ascension-day non-duplication).
- [x] **TASK-1S.3:** `SaveManager` persistence and fail-closed validation for `factions.strategy_executor` (`last_executed_days`, `last_tribe_growth_day`) with legacy save backward compatibility.
- [x] **TASK-1S.4:** Automated test suite `scripts/test/test_faction_strategy_execution.gd` covering TC-FEXEC.1 through TC-FEXEC.14 (PASS, Exit Code 0).

---

## Package 1T: Deterministic Autonomous Faction Diplomacy (Completed)
- [x] **TASK-1T.1:** Pure, deterministic `FactionDiplomacyPlanner` (`scripts/factions/faction_diplomacy_planner.gd`) evaluating autonomous war (`declare_war`) and peace (`sign_peace`) decisions from authoritative `FactionData` thresholds (`WAR_MAX_OPINION = -60.0`, `WAR_MIN_MILITARY_POWER = 65.0`, `WAR_MIN_STABILITY = 50.0`, `PEACE_MAX_MILITARY_POWER = 20.0`, `PEACE_MAX_STABILITY = 25.0`), goal/ascension gating, treaties, and existence status with zero side effects.
- [x] **TASK-1T.2:** `FactionManager` autonomous diplomacy execution (`execute_faction_diplomatic_action`, `get_faction_diplomatic_decision`, `evaluate_all_diplomatic_decisions`, `get_faction_last_diplomacy_day`, signals `diplomatic_action_evaluated` and `diplomatic_action_executed`), routing through `declare_war()` and `propose_treaty(..., "peace")`, executing before daily strategic economic intents in `update_daily_simulation(day)`, and enforcing at-most-once daily evaluation per faction (`_last_diplomacy_days`).
- [x] **TASK-1T.3:** `SaveManager` persistence and fail-closed validation for `factions.strategy_executor.last_diplomacy_days` (`1..36500` and `<= game_clock.current_day`) with second-layer filtering in `FactionManager.deserialize_executor_state()` and legacy save compatibility.
- [x] **TASK-1T.4:** In-Game `HUD` Vietnamese event banner and diplomacy UI refresh integration for both `war_declared` and `peace_signed` signals.
- [x] **TASK-1T.5:** Automated test suite `scripts/test/test_faction_diplomacy_ai.gd` covering TC-FDIP.1 through TC-FDIP.16 (PASS, Exit Code 0).

---

## Package 1U: Pairwise Faction Relations Foundation (Completed)
- [x] **TASK-1U.1:** Canonical pairwise relationship model `FactionRelationData` (`scripts/factions/faction_relation_data.gd`) storing unordered NPC faction pairs `(faction_a < faction_b)` with canonical `pair_key = faction_a + "__" + faction_b`, directional opinions (`opinion_a_to_b`, `opinion_b_to_a` clamped to `[-100.0, 100.0]`), and shared war/treaty state (`is_at_war`, `has_nap`, `has_alliance`).
- [x] **TASK-1U.2:** `FactionManager` pairwise relationship lifecycle, queries (`get_faction_pair_key`, `get_faction_relation_record`, `get_faction_relation`, `get_directed_faction_opinion`, `are_factions_at_war`, `do_factions_have_nap`, `do_factions_have_alliance`, `get_all_faction_relations`), validated atomic mutations (`set_faction_pair_opinion`, `modify_faction_pair_opinion`, `declare_war_between_factions`, `sign_peace_between_factions`, `sign_nap_between_factions`, `sign_alliance_between_factions`, `propose_treaty_between_factions`), and pair-specific signals (`faction_pair_opinion_changed`, `faction_pair_war_declared`, `faction_pair_peace_signed`, `faction_pair_treaty_signed`) isolated from player-facing `FactionData` fields and settlement raids.
- [x] **TASK-1U.3:** `SaveManager` persistence and fail-closed validation for `factions.pairwise_relations` (`SAVE_SCHEMA_VERSION = 1`) with full legacy save compatibility and double-load idempotency.
- [x] **TASK-1U.4:** Automated test suite `scripts/test/test_faction_relation_matrix.gd` covering TC-FREL.1 through TC-FREL.16 (PASS, Exit Code 0).

---

## Package 1V: Functional Automation Graph MVP (Completed)
- [x] **TASK-1V.1:** Implement `AutomationProgram` data model (`scripts/economy/automation_program.gd`) supporting `id`, `name`, `enabled`, `priority`, `nodes`, `edges`, `serialize()`, and `deserialize()`.
- [x] **TASK-1V.2:** Implement strict fail-closed `AutomationGraphValidator` (`scripts/economy/automation_graph_validator.gd`) verifying node types/subtypes, triggers, orphan detection via BFS and data dependency tracing, port/socket compatibility, iterative DFS cycle prevention, and IfElse branching constraints.
- [x] **TASK-1V.3:** Implement graph execution engine in `AutomationManager` (`scripts/economy/automation_manager.gd`) with finite step budget (`MAX_STEPS_PER_RUN = 60`), condition evaluation (`ResourceCompare`, `CitizenFatigue`, `StorageFull`), logic gates (`AND`, `OR`, `NOT`), dynamic IfElse branching, action execution (`AssignRole`, `BoostJobPriority`, `EmitLog`), dry-run immutability guarantee, priority ordering, simulation pause respect, and preset rule non-regression.
- [x] **TASK-1V.4:** Integrate graph persistence into `SaveManager` (`scripts/persistence/save_manager.gd`) under `data["automation"]` with fail-closed validation on malformed graph programs and 100% backward compatibility for legacy saves lacking the `automation` section.
- [x] **TASK-1V.5:** Implement visual graph editor UI `AutomationEditor` (`scenes/ui/automation_editor.tscn`, `scripts/ui/automation_editor.gd`) with `GraphEdit`/`GraphNode` canvas, program selector, node creation palette, parameter inspector, validation badge, dry run simulator with trace output, and wire shortcut `G` and BottomBar button in `HUD`.
- [x] **TASK-1V.6:** Automated test suite `scripts/test/test_automation_graph.gd` covering TC-AGRAPH.1 through TC-AGRAPH.16 (PASS, Exit Code 0: 16/16 tests passed, 69 checks passed).

---

## Package 1W: Tactical Military Units & Command MVP (Completed)
- [x] **TASK-1W.1:** Implement individual visual tactical soldier actor `TacticalUnit` (`scenes/world/tactical_unit.tscn`, `scripts/military/tactical_unit.gd`) with dimetric 2D isometric projection, foot-anchored pivot `(-12, -30)`, Y-sorting, royal military gold attire, ground-circle selection indicator, discrete grid traversal, smooth interpolation, and TimeManager speed/pause support.
- [x] **TASK-1W.2:** Implement `TacticalMilitaryManager` (`scripts/military/tactical_military_manager.gd`) maintaining strict 1:1 synchronization with authoritative `PlayerArmyManager.soldier_count`, selection management (single, Shift additive, screen-space drag box), and spatial formations (`Line`, `Column`, `Scatter`) calculating distinct non-overlapping walkable destination slots.
- [x] **TASK-1W.3:** Implement control groups (`Ctrl+1/2/3` to assign, `Shift+1/2/3` to recall) with dead-unit pruning, isolating them from HUD speed controls so plain `1/2/3` continues controlling simulation speed.
- [x] **TASK-1W.4:** Refine `ArmyMarker` (`scripts/military/army_marker.gd`) into the Strategic Rally Point Banner (`🚩 Điểm tập kết`), maintaining 100% backward compatibility with `test_army_movement.gd` (TC-MOVE.24) while avoiding visual soldier duplication.
- [x] **TASK-1W.5:** Integrate tactical military command UI into `ArmyPanel` in `HUD` (`scripts/ui/hud.gd`) and selection box overlay in `WorldView` (`scripts/world/world_view.gd`) without adding extra buttons to `BottomBar` or breaking responsive layout.
- [x] **TASK-1W.6:** Add persistence and fail-closed validation in `SaveManager` (`scripts/persistence/save_manager.gd`) under `data["tactical_military"]`, with legacy save fallback reconstructing units from `soldier_count` at rally cell.
- [x] **TASK-1W.7:** Automated test suite `scripts/test/test_tactical_military.gd` covering TC-TAC.1 through TC-TAC.30 (PASS, Exit Code 0: 74/74 assertions passed).

---

## Package 1W Follow-Up: Occupancy-Safe Tactical Roster, Fail-Closed Save & Strategic/Tactical Consistency (Completed)
- [x] **TASK-1W-FU.1:** Multi-transaction spawn safety and formation collision avoidance in `TacticalMilitaryManager`: guaranteed distinct, non-overlapping coordinates for sequentially recruited units across multiple transactions, `can_allocate_spawns()` capacity preflight, and slot calculation excluding unselected units.
- [x] **TASK-1W-FU.2:** Fail-closed save validation and legacy reconstruction gating in `SaveManager`: legacy reconstruction restricted to saves where `tactical_military` is completely absent (or legacy `player_army` lacking `movement_state`); presence of malformed, corrupt, or mismatched tactical military data is rejected fail-closed.
- [x] **TASK-1W-FU.3:** Strategic vs Tactical architectural consistency contract documented in `docs/SCOPE_DECISIONS.md` (§1.23): base rally perimeter defined at Manhattan distance <= 5, settlement defense dynamically restricted to garrisoned units, offensive campaigns gated on field units, strategic commands (`order_move`, `order_return_home`) synchronized with tactical layer, and casualties deducted authoritatively without double dipping.
- [x] **TASK-1W-FU.4:** Comprehensive follow-up test suite in `scripts/test/test_tactical_military.gd` covering FU-CASE.1 through FU-CASE.22 (PASS, Exit Code 0: 112/112 assertions passed; full regression across 10 project test suites passed).

---

## Package 1X: Tactical Combat & Enemy Military Entities (Upcoming)
- [ ] **TASK-1X.1:** Real-time tactical combat engagements between player tactical units and hostile forces.
- [ ] **TASK-1X.2:** Enemy military tactical units on the world map with tactical AI behaviors.
- [ ] **TASK-1X.3:** Direct field siege operations and tactical combat victory conditions.
