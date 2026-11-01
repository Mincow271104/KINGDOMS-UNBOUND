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

## Package 1W Final Hardening: Field-Only Campaigns, Strict Save Validation & Movement Integrity (Completed)
- [x] **TASK-1W-FH.1:** Fix A — Field-Only Offensive Campaigns & Location-Restricted Casualties: `BattleCampaignManager.can_launch_offensive_campaign()` and `launch_offensive_campaign()` query and use eligible field units (`get_field_unit_count()`); battle casualties are clamped to eligible attacking force; casualty deduction in `PlayerArmyManager.remove_casualties()` is strictly location-restricted (`from_field = true` never consumes garrisoned units, `from_field = false` never consumes deployed field units); 1:1 parity between `soldier_count` and tactical roster size strictly maintained.
- [x] **TASK-1W-FH.2:** Fix B — Fail-Closed Persistence & Validation-Before-Mutation: `SaveManager.validate_save_data()` enforces moving units have valid `target_cell` and non-empty `current_path` ending at `target_cell`, idle/holding units have empty paths, and tactical unit count matches `player_army.soldier_count` even when `player_army` lacks `movement_state` (removing `is_legacy_army` bypass); `apply_loaded_state_to_world()` fails closed on failed tactical deserialize; `TacticalMilitaryManager.deserialize()` and `TacticalUnit.deserialize()` enforce validation-before-mutation returning `bool` before calling `clear_all_units()`; `test_army_movement.gd` line 916 cleans `legacy_dict` of `tactical_military` key for true legacy save restoration testing.
- [x] **TASK-1W-FH.3:** Fix C — Safe Strategic/Tactical Movement Advancement: `PlayerArmyManager.advance_movement()` delegates stepping to `TacticalMilitaryManager.advance_movement()`, ensuring identical physical movement across runtime and headless test environments; `world_view.gd` prevents double-stepping; forced snapping/teleportation (`arrive_all_at_destination()`) removed; `sync_state_from_tactical()` never clears `current_path` or aborts a march while `movement_state == MARCHING and not current_path.is_empty()`; deterministic 4-part movement contract documented in `docs/SCOPE_DECISIONS.md`.
- [x] **TASK-1W-FH.4:** Fix D — Army Count UI Signals: `PlayerArmyManager.remove_casualties()` unconditionally emits `army_changed.emit(soldier_count, get_army_capacity())` after casualty removal regardless of tactical manager presence, ensuring immediate UI and marker updates without duplicate casualty deductions.
- [x] **TASK-1W-FH.5:** Automated hardening test suite in `scripts/test/test_tactical_military.gd` covering FH-CASE.1 through FH-CASE.10 (PASS, Exit Code 0: 145/145 assertions passed; all 10 project regression test suites passed with 0 failures).

---

## Package 1W Post-Hardening Review: Garrison Return, Ready Field Force & Casualty Eligibility (Completed)
- [x] **TASK-1W-PH.1:** Fix A — Dedicated Garrison Return Allocation & State Consistency: `TacticalMilitaryManager.compute_garrison_return_slots()` implements dedicated deterministic outward spiral slot search strictly bounded to `RALLY_PERIMETER_DISTANCE = 5`, disallowing slots outside perimeter; `order_return_all_to_rally()` checks slot availability and fails closed atomically with 0 partial dispatch; `PlayerArmyManager.order_return_home()` propagates return command failures without clearing route or setting garrisoned; `PlayerArmyManager._arrive_at_destination()` maintains `MARCHING` while tactical units are still in transit to perimeter slots; `sync_state_from_tactical()` finalizes state to `GARRISONED` once all units are idle within perimeter, preventing any reversion to `IDLE_AT_FIELD`.
- [x] **TASK-1W-PH.2:** Fix B — Ready Field Troops & Campaign Consistency: `TacticalMilitaryManager.get_field_units()` and `PlayerArmyManager.get_field_unit_count()` strictly require `order_state != MOVING and dist > RALLY_PERIMETER_DISTANCE`, defining ready field troops; `BattleCampaignManager.can_launch_offensive_campaign()` and `launch_offensive_campaign()` use this identical predicate for the offensive campaign gate and `atk_troops`; moving field units are never counted as assembled offensive participants; campaigns fail closed if ready field troops == 0.
- [x] **TASK-1W-PH.3:** Fix C — Defensive vs. Offensive Casualty Predicate Consistency: `TacticalMilitaryManager.sync_with_player_army()` strictly disallows moving units as casualties in either theater (`if u.order_state == MOVING: return false`); defensive raid casualties are drawn strictly from stationary garrisoned units (`dist <= 5 and order_state != MOVING`); field campaign casualties are drawn strictly from stationary field units (`dist > 5 and order_state != MOVING`); clamping to eligible stationary pool guarantees authoritative 1:1 roster parity `soldier_count == units.size()`.
- [x] **TASK-1W-PH.4:** Fix D — Hardened Integration Tests: FH-CASE.2 verified for non-vacuous player casualties ($\ge 1$); FH-CASE.3 upgraded to exercise actual `BattleCampaignManager.resolve_and_apply_raid()` resolution path; FH-CASE.8b tests `SaveManager.apply_loaded_state_to_world()` on corrupted tactical data; PH-CASE.1 to PH-CASE.8 implement 12- and 20-soldier full return-home in Line formation, slot exhaustion atomic rejection, blocked route failure propagation, moving field subset exclusion, zero stationary field troops gate rejection, defensive casualty stationary vs. moving selection, and inverse field casualty selection. (PASS, Exit Code 0: 204/204 assertions passed in `test_tactical_military.gd`).
- [x] **TASK-1W-PH.5:** Final Review — Idempotent Return-Home Commands, Strict GARRISONED Gating & Non-Vacuous Tests: `TacticalUnit.order_move()` preserves `step_accumulator` and path when reissuing identical move commands; `TacticalMilitaryManager.order_return_all_to_rally()` pre-validates slots and paths atomically before dispatching or mutating selection; `PlayerArmyManager.order_return_home()` and `_arrive_at_destination()` strictly guard against premature `GARRISONED` transition while tactical units are in transit (`are_all_tactical_units_settled_at_base()`); FH-CASE.3 upgraded with dedicated split-army fixture ($\ge 1$ field and $\ge 1$ garrison units guaranteed); PH-CASE.3 tests real dispatcher atomic rejection and selection preservation; PH-CASE.4 tests strategic wrapper route failure propagation with trapped tactical unit and reissued route invariance; PH-CASE.9 validates repeated-command return-home regression (PASS, Exit Code 0: 252/252 assertions passed in `test_tactical_military.gd`).
- [x] **TASK-1W-PH.6:** Garrison Transition Audit — Strict Invariant Enforcement & Integrated Restore: `PlayerArmyManager` strictly guards every transition to `MovementState.GARRISONED` via shared helper `get_settled_state_for_cell()`; `cancel_move()` halts strategic route while preserving in-transit `MARCHING` state for moving tactical units and `IDLE_AT_FIELD` for units halted outside perimeter; dynamic obstruction reroute failure in `advance_movement()` and invalid route recovery in `deserialize()` strictly respect the settlement invariant; `sync_state_from_tactical()` transitions `movement_state` from `GARRISONED` to `MARCHING` if any tactical unit is moving; `SaveManager` calls `sync_state_from_tactical()` following tactical military deserialization to guarantee restored world consistency; verified by GTA-CASE.1, GTA-CASE.2, and GTA-CASE.3 (PASS, Exit Code 0: 285/285 assertions passed in `test_tactical_military.gd`).
- [x] **TASK-1W-PH.7:** Final Invariant Audit — Deserialization Garrison Gating & Empty Tactical Roster Fail-Closed: `PlayerArmyManager.deserialize()` avoids premature `GARRISONED` publishing during Step 13 when `soldier_count > 0` before Step 17 restores tactical units; direct `deserialize()` reconciles immediately against matching tactical units; `PlayerArmyManager.is_deserializing` flag isolates `TacticalMilitaryManager._on_army_changed` from auto-spawning dummy units during save restoration; `are_all_tactical_units_settled_at_base()` strictly returns `false` if `soldier_count > 0` and roster is empty or mismatched; `sync_state_from_tactical()` immediately clears `GARRISONED` and sets `IDLE_AT_FIELD` when `soldier_count > 0` and roster is empty; `SaveManager.validate_save_data()` strictly fails closed on empty or mismatched tactical units for positive soldier counts; genuine 0-soldier army normalizes to `GARRISONED` at `rally_cell`; verified by GTA-CASE.4, GTA-CASE.5, GTA-CASE.6, and GTA-CASE.7 (PASS, Exit Code 0: 308/308 assertions passed in `test_tactical_military.gd`; all 11 test suites passing).
- [x] **TASK-1W-PH.8:** Consolidated Final Audit, Invariant Fix & Closure: Truthful Garrison State Invariant strictly enforced across all state transitions; `are_all_tactical_units_settled_at_base()` and `get_settled_state_for_cell()` strictly return `false` / `IDLE_AT_FIELD` when `tactical_military_mgr == null` and `soldier_count > 0`; `TacticalMilitaryManager._init()` and `set_player_army_manager()` establish bi-directional pairing with `PlayerArmyManager`; `order_return_home()` converges cleanly on `idle_at_rally` (`IDLE_AT_FIELD`) when tactical units are stationary outside perimeter without manager; automated test cases GTA-CASE.8 to GTA-CASE.11 verified (PASS, Exit Code 0: 334/334 assertions passed in `test_tactical_military.gd`; full regression suite passed).
- [x] **TASK-1W-PH.9:** Final Roster Lifecycle Patch & Closure: Made `can_recruit()` strictly read-only with zero state mutations, guarding with `soldier_count > 0` and `current_cell != rally_cell` allowing base recruitment without manager while blocking field recruitment; `recruit()` safely normalizes to `IDLE_AT_FIELD` when manager is missing while preserving atomic resource deduction; `set_tactical_military_manager(mgr)` runtime detachment transitions non-empty army from `GARRISONED` to `IDLE_AT_FIELD`; direct `deserialize({})` invokes `clear_all_units()` freeing active/moving ghost units immediately; `get_settled_state_for_cell()` and `sync_state_from_tactical()` verify roster emptiness before allowing zero-soldier `GARRISONED`; automated test cases GTA-CASE.12 through GTA-CASE.15 verified (PASS, Exit Code 0: 371/371 assertions passed in `test_tactical_military.gd`; all 11 test suites passing).
- [x] **TASK-1W-PH.10:** Final Detachment Symmetry Fix: Implemented symmetric manager detachment and replacement across `PlayerArmyManager` and `TacticalMilitaryManager`; disconnected signals (`army_changed`, `tactical_state_updated`), cleared back-references with recursion protection, and cleaned rosters on detachment (`clear_all_units()`), eliminating ghost units; enforced authoritative manager check `player_army_mgr.get("tactical_military_mgr") == self` in `_on_army_changed` and `sync_with_player_army` preventing detached managers from recreating rogue units; regression test in GTA-CASE.14 verified recruitment while detached, authoritative roster reconstruction upon re-attachment, and reverse detachment (PASS, Exit Code 0: 385/385 assertions passed in `test_tactical_military.gd`; all 11 test suites passing).

---

## Package 1X: Tactical Combat, Enemy Military AI & Field Siege (Completed)
- [x] **TASK-1X.1:** Real-Time Tactical Combat: Data-driven combat properties on `TacticalUnit` (`health`, `max_health`, `attack_damage`, `attack_range`, `attack_cooldown`, `is_alive`, `faction_id`), visual health bar indicators, white damage flash timers, Manhattan distance checking, attack order state machine (`OrderState.ATTACKING`), right-click attack targeting for hostile entities, deterministic simulation combat stepping honoring `TimeManager` pause and speed scaling (1x/2x/3x), friendly fire prevention, target auto-disengagement upon target death, and strict 1:1 casualty parity with `PlayerArmyManager.soldier_count` decremented on player tactical unit death.
- [x] **TASK-1X.2:** Enemy Military Entities & Tactical AI: Implemented `EnemyTacticalUnit` (`scripts/military/enemy_tactical_unit.gd`) with crimson modulate `Color(0.95, 0.3, 0.3, 1.0)`, deterministic AI state machine (`HOLD`, `PATROL`, `ACQUIRE_TARGET`, `PURSUE`, `ATTACK`, `RECOVER_RETREAT`), sorted-ID deterministic update iteration in `EnemyMilitaryManager` (`scripts/military/enemy_military_manager.gd`), procedural spawning on distinct walkable cells (`spawn_enemy_unit`, `spawn_enemy_force`), casualty cleanup, and immediate cessation of hostilities and retreat upon signing a peace treaty.
- [x] **TASK-1X.3:** Field Siege Operations & Combat Victory Conditions: Implemented `SiegeObjectiveActor` (`scripts/combat/siege_objective_actor.gd`) representing captureable hostile outposts and strongholds with isometric health bars, damage absorption, and capture transitions; implemented `FieldSiegeManager` (`scripts/combat/field_siege_manager.gd`) with eligibility gating (active faction, at war, assembled field army outside garrison perimeter), siege launch with defender mobilization, deterministic combat resolution (Victory, Defeat, Withdrawal), plunder rewards (Gold, Food, Metal), faction military power reduction, coexistence with `BattleCampaignManager`, and fail-closed persistence under `SaveManager` (`"field_siege"` and `"enemy_military"`).
- [x] **TASK-1X.4:** Package 1X Final Gameplay Integration & Persistence Closure:
  - Wire gameplay lifecycle in `WorldView`: registered deterministic, walkable, in-bounds outposts for rival factions (`rival_military`, `rival_merchant`, `neutral_tribe`) avoiding buildings/obstacles/citizens/units; connected `FactionManager.war_declared` signal to idempotent enemy force spawning and `peace_signed` signal to cessation of hostilities, retreat, and siege cancellation; wired player right-click siege initiation on outposts with eligibility checks and Vietnamese rejection banners.
  - Enforce siege eligibility on objectives: `SiegeObjectiveActor` requires `is_under_active_siege == true` before taking damage or emitting damage/destroyed signals; `TacticalMilitaryManager.issue_attack_order()` rejects attack orders on un-sieged outposts; defenders mobilize on siege launch.
  - Canonical resource economy: replaced `"iron"` with `EconomyConfig.RES_METAL` (`"metal"`) in `FieldSiegeManager.PLUNDER_REWARDS` with atomic `ResourceManager` integration, storage bounding, and HUD/save compatibility.
  - Fail-closed validation & atomic restoration: added deep validation in `SaveManager.validate_save_data()` for `enemy_military` (stats, coordinates, paths, states) and `field_siege` (objectives, active sieges); implemented atomic validation-before-mutation in `EnemyMilitaryManager.deserialize()` and `FieldSiegeManager.deserialize()`; safe fallback for unresolved combat targets to `OrderState.IDLE`.
  - Patrol behavior completion: implemented perimeter return and obstacle-aware navigation in `EnemyTacticalUnit._ai_tick_patrol()`.
  - Automated integration test suite `scripts/test/test_package_1x_gameplay_integration.gd` (39 assertions, PASS, exit 0) and additions across test suites.
- [x] **TASK-1X.5:** Package 1X Final Enemy Spawn, Occupancy & Siege Retry Fix:
  - Authoritative spawn-slot entity exclusion policy: implemented `EnemyMilitaryManager.get_authoritative_occupied_cells()` and `is_cell_spawn_eligible()` strictly excluding registered siege objective cells, living enemy units, living player tactical units, living citizens (using safe `cit.has_method("is_alive")` / `cit.call("is_alive")` callable check), building footprints, and water tiles.
  - Objective cell overlap immunity: initial war deployment (`WorldView._on_faction_war_declared`) and siege defender placement (`FieldSiegeManager.launch_field_siege`) never place an enemy on an objective's cell (`exclude_center = true`).
  - Outpost targeting click priority: `WorldView._unhandled_input()` prioritizes exact-cell siege objective clicks over fuzzy adjacent enemy targeting, ensuring direct outpost right-clicks are never intercepted.
  - Single explicit distinction between faction field forces and objective defenders: added `@export var is_garrison_defender: bool` and `@export var assigned_objective_id: String` to `EnemyTacticalUnit`, preserved in serialization; `FieldSiegeManager.launch_field_siege()` reuses living defenders, assigns eligible nearby faction units, and spawns only missing defenders up to `garrison_count` on retry, preventing unbounded enemy inflation; on victory, surviving defenders of the captured outpost retreat and despawn.
  - Automated test suites: added TC-SIEGE.14 and TC-SIEGE.15 in `scripts/test/test_field_siege.gd` (85/85 assertions passed) and TC-INT.7 and TC-INT.8 in `scripts/test/test_package_1x_gameplay_integration.gd` (57/57 assertions passed).

---

## Package 1Y: Automation Graph Delay & Repeat Nodes (Completed)
- [x] **TASK-1Y.1:** Bounded Delay Node & Simulation Clock Continuations:
  - Validated integer `duration_hours` bounded between 1 and 720 hours (up to 30 game days).
  - Flow ports (`in` -> `out`) that suspend execution upon reaching the Delay node.
  - Scheduled continuations stored with `id`, `program_id`, `node_id`, `resume_node_id`, `duration_hours`, `due_day`, `due_hour`, and absolute simulation clock `due_total_hours = (due_day - 1) * 24 + due_hour`.
  - Queue limits: global cap `MAX_GLOBAL_PENDING_CONTINUATIONS = 50`, per-program cap `MAX_PROGRAM_PENDING_CONTINUATIONS = 10` failing closed with informative error codes.
  - Clean lifecycle: deletion of programs cleans pending continuations; disabled programs skip continuation resumes; paused simulation freezes execution; 1h delays execute on the next eligible simulation hour; day boundary transitions calculate exact `due_day` and `due_hour`.
- [x] **TASK-1Y.2:** Bounded Repeat Node & Budget Safety:
  - Validated integer `count` bounded between 1 and 20 iterations.
  - Dual control-flow outputs: Slot 0 `body` for the loop iteration body and Slot 1 `completed` for post-loop execution.
  - Strict DAG enforcement: graph cycle detection continues rejecting cycles and back-edges, preventing infinite recursion while enabling finite visual loops.
  - Execution budget safety: increments step budget on every node execution within iterations, safely terminating execution if combined steps reach `MAX_STEPS_PER_RUN = 60`.
- [x] **TASK-1Y.3:** Visual Editor Integration:
  - Palette buttons `AddDelayBtn` ("⏳ Trì hoãn") and `AddRepeatBtn` ("🔁 Lặp lại") added to `scenes/ui/automation_editor.tscn`.
  - GraphNode slot configurations, port mapping helpers (`body` -> 0, `completed` -> 1), dynamic title/label formatters, and inspector spinbox controls in `scripts/ui/automation_editor.gd` with live node parameter mutation and graph refresh.
- [x] **TASK-1Y.4:** Strict Graph Validation:
  - Added `"Delay"` and `"Repeat"` to `VALID_NODE_TYPES` in `scripts/economy/automation_graph_validator.gd`.
  - Enforced strict integer range validation for `duration_hours` (1–720) and `count` (1–20).
  - Enforced flow-to-boolean and boolean-to-flow connection incompatibility.
  - Enforced required outgoing edges: Delay requires `out`; Repeat requires `body` or `out`.
- [x] **TASK-1Y.5:** Side-Effect-Free Dry Run:
  - Full trace simulation for Delay (logging scheduled resume day/hour without queuing continuations) and Repeat (logging iterations and completed step without mutating citizens, jobs, or resources).
- [x] **TASK-1Y.6:** Save/Load Persistence & Schema Compatibility:
  - Added fail-closed schema validation in `SaveManager` for `pending_continuations` (validating types, ID strings, program IDs, node IDs, integer duration 1–720, due_day >= 1, due_hour 0–23, due_total_hours >= 0).
  - Maintained schema version 1 compatibility; legacy saves lacking continuations load cleanly with an empty queue.
  - Verified double-load idempotency without duplicate continuation records.
- [x] **TASK-1Y.7:** Automated Test Suite:
  - Implemented `scripts/test/test_automation_graph_delay_repeat.gd` covering 7 test groups and 110 assertions (110/110 passed, Exit Code 0).
  - Verified full regression matrix across all 21 project test suites with 0 failures.
- [x] **TASK-1Y.8:** Package 1Y Final Repeat/Delay Lifecycle and Persistence Fix:
  - Preserved Repeat state across delayed continuations: encountering a Delay node within a Repeat loop iteration schedules downstream continuation with `repeat_node_id`, `repeat_iteration`, `repeat_count`, and `steps_used`, suspending the Repeat loop without prematurely executing subsequent iterations or the `completed` branch.
  - Unified Repeat execution and resumption: `_execute_repeat_node()` handles both fresh Repeat runs and continuation resumptions. Resumed iterations execute strictly from `resume_node_id` without replaying pre-delay actions or triggers; subsequent iterations restart fresh from the Repeat body; once all iterations finish, `completed` output is triggered exactly once.
  - Fresh condition evaluation per iteration: allocated `iter_memo_bool = {}` per iteration so dynamic simulation conditions evaluate fresh without stale memoization bleeding across loop iterations.
  - Step budget bounding: step budget is carried across continuations via `steps_used`, bounding total logical execution steps across delayed resumptions to `MAX_STEPS_PER_RUN = 60`.
  - Rejection of nested Repeat: `AutomationGraphValidator` traverses body branches to reject nested Repeat structures fail-closed.
  - Deep validation & atomic fail-closed persistence: unified validation in `AutomationManager.validate_automation_data()` and `validate_pending_continuations()`, checking unique IDs, program/node existence, delay parameters, due-time formulas (`due_total_hours == (due_day - 1) * 24 + due_hour`), Repeat metadata (valid Repeat node, matching count, iteration <= count, steps_used <= 60), and queue limits. `AutomationManager.deserialize()` validates first and stages all variables, returning `false` on malformed data without mutating live state.
  - Extended regression suite: added Group 8 to `scripts/test/test_automation_graph_delay_repeat.gd` (total 169/169 assertions passed, Exit Code 0).
- [x] **TASK-1Y.9:** Final Repeat Continuation Metadata Validation Fix:
  - Enforced all-or-nothing Repeat metadata validation in `AutomationManager.validate_pending_continuations()`: `repeat_node_id`, `repeat_iteration`, `repeat_count`, and `steps_used` form a single required logical unit for Repeat continuations.
  - Implemented graph reachability detector `AutomationManager.find_enclosing_repeat_node()` to identify Delay nodes structurally located within a Repeat body branch.
  - Prohibited omitting Repeat metadata for Delay nodes located inside a Repeat body; prohibited Repeat metadata referencing unrelated Repeat nodes.
  - Validated that `resume_node_id` is an authoritative downstream target connected from the continuation's `delay_node_id`'s `out` port.
  - Preserved complete backward compatibility for normal Delay continuations outside Repeat bodies (which do not require Repeat metadata and accept optional `steps_used`).
  - Added dedicated test suite TC-Y.37 (TC-Y.37.1 to TC-Y.37.9) to `scripts/test/test_automation_graph_delay_repeat.gd`, expanding suite to 179/179 assertions passing with exit code 0.

## Package 1Z — Legacy Fund & Meta-Progression Foundation
- [x] **TASK-1Z.1:** Authoritative Legacy profile data model outside individual world-save data:
  - Created `scripts/legacy/legacy_profile_manager.gd` managing persistent profile fields: `profile_id`, `legacy_balance`, `lifetime_legacy_earned`, `lifetime_legacy_spent`, `claimed_rewards`, `unlocked_achievements`, `schema_version = 1`.
  - Maintained mathematical invariants: `legacy_balance == lifetime_legacy_earned - lifetime_legacy_spent` and `sum(claimed_rewards.amount) == lifetime_legacy_earned`.
- [x] **TASK-1Z.2:** Dedicated profile persistence path and corruption recovery:
  - Persisted profile to `user://legacy_profile.json` using atomic temporary writes (`.tmp`) and backup rotation (`.bak`).
  - Added fail-closed schema validation before mutating memory or writing to disk.
  - Implemented automatic recovery from `.bak` when primary file is corrupted. If both primary and backup are corrupted, fails closed and preserves live in-memory state without destructive resets.
  - Allowed isolated custom filepaths for test execution.
- [x] **TASK-1Z.3:** Centralized authoritative exactly-once reward-claim API:
  - Implemented `claim_reward(reward_id, source, amount, world_id, extra_details)` in `LegacyProfileManager`.
  - Rejects duplicate claims by `reward_id`, returning 0 points awarded and leaving balance unchanged.
  - Validates allowed sources (`victory`, `achievement`) and positive integer amounts fail-closed.
  - Performs atomic rollback on disk write failure to maintain in-memory and disk symmetry.
- [x] **TASK-1Z.4:** Victory reward integration:
  - Extended `VictoryManager` to connect with `LegacyProfileManager` using stable world-scoped reward identifier (`victory_<world_id>`).
  - Awarded 100 Legacy points exactly once per world upon achieving Prosperity Victory after continuous 5-day hold.
  - Reloading an earlier save of the same world detects existing claim in profile and awards 0 additional points.
  - Distinct worlds with different `world_id`s can each legitimately claim victory once.
  - Preserved fallback behavior for headless tests without profile manager.
- [x] **TASK-1Z.5:** Achievement reward foundation:
  - Seeded achievement registry with documented `prosperity_victory` achievement (100 Legacy points).
  - Unlocked automatically upon victory achieved via `profile_mgr.unlock_achievement("prosperity_victory", world_id)`.
  - Profile-level achievement can only be awarded once across all worlds and saves.
  - Documented intentional gap for ungrounded/undocumented achievements.
- [x] **TASK-1Z.6:** Stable treasury conversion extension point:
  - Implemented `convert_surplus_treasury()` in `LegacyProfileManager` returning `status: "deferred"`, 0 legacy points awarded, and 0 gold deducted.
  - Explicitly deferred pending authoritative design decisions for formula, threshold, and conversion rate per GDD §13.2.
- [x] **TASK-1Z.7:** Minimal UI integration:
  - Added persistent Legacy balance display (`LegacyFundLabel`) to `MainMenu` (`scenes/ui/main_menu.tscn` / `scripts/ui/main_menu.gd`) reacting dynamically to `balance_changed`.
  - Added claim button (`ClaimVictoryBtn`) and status label (`LegacyStatusLabel`) to `VictoryPanel` in `InGameHUD` (`scenes/ui/hud.tscn` / `scripts/ui/hud.gd`), accurately reflecting authoritative claim state without double claiming.
- [x] **TASK-1Z.8:** Automated Test Suite:
  - Created headless test suite `scripts/test/test_legacy_fund.gd` covering 15 scenarios (15/15 passed, Exit Code 0).
  - Full regression test run verified across existing packages (Phase 7, Save/Load, Automation Graph, Automation Delay/Repeat, Factions & Battles, Tactical Military, Field Siege) with zero regressions.
- [x] **TASK-1Z.AUDIT:** Post-Implementation Audit & Critical Hardening Fixes:
  - **FIX-1Z-A (Double Legacy Reward Elimination):** Deferred direct points from `prosperity_victory` achievement (`reward_legacy: 0`, `reward_status: "deferred"`), keeping `claim_reward("victory_" + world_id, "victory", 100, world_id)` as the authoritative single source of victory points (ensuring 1 victory = exactly 100 Legacy points total).
  - **FIX-1Z-B (Transactional Achievement Unlock & Memory Rollback):** Added achievement ID validation against registry, staged memory mutations, and implemented atomic in-memory rollback if disk write fails. Never creates fabricated claim records when `reward_legacy == 0`.
  - **FIX-1Z-C (Unique Persistent World IDs & Legacy Save Migration):** Eliminated `world_<seed>` collision bug by implementing `WorldView.generate_unique_world_id()`; updated `SaveManager` to migrate legacy saves missing `world_id` and persist them immediately; gated claims via `is_world_id_persisted` to block unsafe claims if disk persistence fails.
  - **FIX-1Z-D (Fail-Closed Profile Initialization & Error Propagation):** Added explicit status tracking (`STATUS_UNINITIALIZED`, `STATUS_NEW_PROFILE`, `STATUS_LOADED`, `STATUS_RECOVERED_FROM_BACKUP`, `STATUS_UNAVAILABLE`); when corrupted, preserves files without wiping to 0, blocks claims, and propagates unavailable state to UI.
  - **Expanded Testing:** Expanded `scripts/test/test_legacy_fund.gd` to 25 automated tests covering all 10 explicit audit requirements with 0 failures.
- [x] **TASK-1Z.HARDENING-2:** Second Hardening Audit: Reward ID Security, Atomic Persistence & Safe Backup Recovery:
  - **FIX-1Z-E (Canonical Exactly-Once Victory Reward IDs):** In `VictoryManager`, prosperity victories strictly enforce the canonical reward ID `victory_<world_id>`. Deprecated `custom_reward_id` parameter is ignored to eliminate exploit cycling; claims and claimability checks synchronize `is_legacy_claimed` directly from profile state and reject unpersisted/invalid world IDs.
  - **FIX-1Z-F & FIX-1Z-H (Hardened Profile Atomic Persistence & Safe Backup Recovery):** In `LegacyProfileManager.save_profile()`, directory access is verified fail-closed, write/flush errors are checked, and `.tmp` is validated via schema inspection before replacing target. During backup rotation, `target_path` is only copied to `.bak` if it passes schema validation; corrupted primary files never overwrite valid backups.
  - **FIX-1Z-G (SaveManager Atomic Write Hardening):** In `SaveManager.save_dict_to_file()`, directory access and write/flush errors are validated; if backup copying fails (`dir.copy != OK`), the operation aborts immediately and preserves the primary file untouched; rename errors trigger backup restoration.
  - **FIX-1Z-I (Accurate HUD Reward Status Classification):** In `InGameHUD._refresh_victory_claim_state()`, decoupled `is_claimed` from `not is_reward_claimable()`, accurately differentiating 6 independent states: already claimed ("Đã Nhận Di Sản"), profile unavailable ("Hồ Sơ Lỗi (Không Thể Nhận)"), unpersisted world ("Chưa Lưu Thế Giới"), invalid world ID ("ID Thế Giới Không Hợp Lệ"), claimable ("Nhận Di Sản (+100)"), and unmet conditions ("Chưa Đạt Điều Kiện").
  - **FIX-1Z-J (64-Bit Numeric Overflow Protection):** Enforced `MAX_SAFE_INT = 9223372036854775807` across `_is_valid_integer_val()`, `validate_profile_data()`, `claim_reward()`, and `unlock_achievement()`, rejecting any transaction or state that would overflow 64-bit integer bounds fail-closed.
  - **Expanded Testing:** Expanded `scripts/test/test_legacy_fund.gd` to 30 comprehensive automated tests (30/30 passed, Exit Code 0). Verified full regression matrix with 0 failures across all project test suites.
- [x] **TASK-1Z.HARDENING-3:** Third Hardening Audit: Fail-Closed Rewards, World ID Lifecycle & Backup Recovery Safety:
  - **FIX-1Z-K (Fail-Closed Victory Rewards & Elimination of Non-Persistent Fallback):** Completely removed null-profile memory fallback in `VictoryManager.claim_legacy_reward()`. `profile_mgr` is strictly mandatory for persistent claims. When `profile_mgr == null` or unavailable, claims return 0, award no memory points, and leave `is_legacy_claimed = false`.
  - **FIX-1Z-L (World ID Persistence Lifecycle & Unsaved Game Gating):** Initialized `is_world_id_persisted: bool = false` as default on `WorldView` and `VictoryManager`. Unsaved games cannot claim victory rewards (`is_reward_claimable() == false`). Saving via `SaveManager` sets `is_world_id_persisted = true`. Generating new world IDs on save migration resets persistence flag until write succeeds.
  - **FIX-1Z-M (Atomic Staged Backup Rotation & Comprehensive Recovery):** Implemented staged backup rotation via `bak_tmp_path` in `SaveManager.save_dict_to_file()`. Validates existing primary save before rotating; preserves valid `.bak` if primary is corrupted; verifies staged copy before replacing `.bak`; automates rollback on target rename error; supports seamless recovery from `.bak` in `load_from_file()` with migrations directed to `canonical_path`; validated across 10 failure injection scenarios.
  - **FIX-1Z-N (64-Bit Float Boundary Precision & Overflow Safety):** Fixed IEEE 754 float64 boundary precision bug where float representations of $2^{63}-1$ round to $2^{63} = 9223372036854775808.0$. Defined strict bounds `FLOAT_INT64_EXCLUSIVE_UPPER = 9223372036854775808.0` and `FLOAT_INT64_INCLUSIVE_LOWER = -9223372036854775808.0`, rejecting values with `f < LOWER or f >= UPPER` in both `LegacyProfileManager` and `SaveManager`.
  - **Automated Test Expansion:** Expanded `scripts/test/test_legacy_fund.gd` to 34 comprehensive automated tests covering all 4 hardening fixes with 100% pass rate (Exit Code 0). Verified full regression test matrix across all 10 project suites with 0 failures.
- [x] **TASK-1Z.HARDENING-4:** Fourth Corrective Audit: Backup Integrity, Recovery Failure Testing & Float64 Boundary Verification:
  - **FIX-1Z-O (Staged Backup Verification Before Replacement):** In `SaveManager.save_dict_to_file()` and `LegacyProfileManager.save_profile()`, reopened and parsed staged backup file (`.bak.tmp`), checking schema and data equivalence against previous primary state before touching or replacing authoritative `.bak`. Replaces `.bak` only after staged copy validation passes, and preserves existing backup on failure.
  - **FIX-1Z-P (Backup Replacement Failure Injection & Recovery Validation):** Added dedicated injection seam `_test_inject_fail_backup_rename` simulating staged backup rename failure with rollback to `.bak.old`. Added `_test_inject_fail_backup_validate`. Strengthened Case 5 to verify restored primary's actual score/data, and Case 6 to verify that remaining backup remains valid and recoverable when primary restoration fails.
  - **FIX-1Z-Q (Profile Recovery Under Interrupted Writes & Restart):** Added comprehensive test verifying profile recovery from `.bak`, followed by failed write rollback, clean restart recovery without duplicate or lost rewards, and backup preservation under rename failure.
  - **FIX-1Z-R (Representable Float64 Lower-Bound & Precision Verification):** Corrected boundary tests to use representable Float64 value `-9223372036854777856.0` ($-2^{63}-2048$). Verified directly that `_is_valid_integer_val` and schema validators on both `LegacyProfileManager` and `SaveManager` accept inclusive lower boundary ($-2^{63}$), reject `-9223372036854777856.0`, reject $2^{63}$, and accept largest representable float below $2^{63}$ ($9223372036854774784.0$).
  - **FIX-1Z-S (Canonical Path Preservation During Backup Recovery & Migration):** Verified that recovering a legacy save from `.bak` migrates world ID by saving to `canonical_path`, never touching or corrupting `.bak`. Verified byte-for-byte invariance of `.bak`, verified returned paths (`path`, `source_path`, `recovered_from_backup`), verified `migration_save_failed` flag sets `is_world_id_persisted = false`, and verified later successful save establishes persisted status.
  - **Automated Test Expansion:** Expanded `scripts/test/test_legacy_fund.gd` to 36 automated tests (36/36 passed, Exit Code 0). Verified full regression test matrix across all 10 project suites with 0 failures.
- [x] **TASK-1Z.HARDENING-5:** Fifth Corrective Audit: Crash-Safe Backup Journal, Strict Save Schema & Profile Restore Failure:
  - **FIX-1Z-T (Crash-Safe `.bak.old` Recovery and Reconciliation):** Implemented crash-safe backup reconciliation (`_reconcile_backups()`) in both `SaveManager` and `LegacyProfileManager`. Validates primary, `.bak`, and `.bak.old` before any cleanup; never deletes the only remaining known-good backup; promotes `.bak.old` to `.bak` if `.bak` is missing or invalid; deterministically preserves the newer valid state when both exist. Extended `load_from_file()` and `load_profile()` to recover from `.bak.old` if primary and `.bak` are unavailable. Subsequent save operations reconcile interrupted rotations before cleaning temporary files, validating all rename, remove, and copy return codes. Added simulated crash-state test suites for both systems.
  - **FIX-1Z-U (Strict and Consistent World-Save Schema Validation):** In `SaveManager`, modified `_read_and_validate_save_file()` to unconditionally validate full schema via `validate_save_data()`, strictly rejecting syntactically valid JSON missing `schema_version` or containing invalid schema. In `save_dict_to_file()`, added upfront validation of incoming production world-save data, rejecting invalid inputs immediately without touching disk files. Schema-invalid primary files are never rotated into authoritative backups. Updated existing test fixtures using dummy schema-less data to use complete, valid world-save fixtures.
  - **FIX-1Z-V (Explicit Legacy Profile Restore-Copy Failure Injection):** Added dedicated test injection seam `_test_inject_fail_restore_copy` in `LegacyProfileManager`, distinct from `_test_inject_fail_rename`, reset via `reset_test_injection()`. Implemented comprehensive 11-step test validating profile recovery from `.bak`, followed by a transaction with simultaneous rename failure and backup restore-copy failure: verified `save_failed` reason, in-memory rollback, backup preservation, and subsequent recovery by a fresh manager instance.
  - **Automated Test Expansion:** Expanded `scripts/test/test_legacy_fund.gd` to 40 comprehensive automated tests (40/40 passed, Exit Code 0). Verified full 10-suite regression matrix across all existing packages with 0 failures and verified Godot headless editor check with exit code 0.
- [x] **TASK-1Z.HARDENING-6:** Sixth Corrective Audit: Profile Reset Safety, Backup Reconciliation Coverage & Exact Backup Preservation:
  - **FIX-1Z-W (Profile Reset Safety Against Backup Resurrection):** In `LegacyProfileManager.reset_profile()`, extended artifact cleanup to remove all 5 files (`target_path`, `.bak`, `.bak.old`, `.tmp`, `.bak.tmp`), checking all remove return codes and verifying file absence on disk. If any artifact removal fails or fails disk verification, `reset_profile()` aborts fail-closed, transitions `profile_status` to `STATUS_UNAVAILABLE`, sets `initialization_error`, and returns `false`. Only transitions to `STATUS_NEW_PROFILE`, resets balances, and emits `balance_changed` when all artifacts are confirmed removed. Added test injection seam `_test_inject_fail_reset_cleanup`.
  - **FIX-1Z-X (Comprehensive Backup Reconciliation Test Coverage):** Added dedicated test suites for both `SaveManager` and `LegacyProfileManager` verifying both core reconciliation cases:
    - Case A: Invalid/corrupt `.bak` + valid `.bak.old`: Verifies data recovery from `.bak.old`, promotion of `.bak.old` to `.bak` upon subsequent save, removal of old file, and restart recovery from promoted `.bak`.
    - Case B: Both `.bak` and `.bak.old` valid: Verifies precedence of `.bak` over `.bak.old`, removal of obsolete `.bak.old` upon subsequent save, preservation of `.bak`, and restart recovery.
  - **FIX-1Z-Y (Byte-for-Byte Exact Backup Preservation):** Strengthened profile restore failure test to capture `PackedByteArray` before failure and compare against backup bytes after failure, verifying byte-for-byte exact preservation of `.bak`. Updated test cleanup helpers to purge `.bak.old` and `.bak.tmp`.
  - **Automated Test Expansion:** Expanded `scripts/test/test_legacy_fund.gd` to 43 comprehensive automated tests (43/43 passed, Exit Code 0). Verified full 10-suite regression matrix across all existing packages with 0 failures and verified Godot headless editor check with exit code 0.
- [x] **TASK-1Z.HARDENING-7:** Seventh Corrective Audit: Missing Primary Save Handling & Genuine Reset-Cleanup Failure Injection:
  - **FIX-1Z-Z (Guarded Primary Save Removal in `save_profile()`):** In `LegacyProfileManager.save_profile()`, explicitly isolated and guarded `target_path` removal with `if FileAccess.file_exists(target_path):`. If the primary save does not exist (such as during post-reconciliation saves from backup recovery), removal is skipped safely, allowing the validated `.tmp` file to be renamed directly to `target_path`. If `target_path` exists, validates `dir.remove()` return code fail-closed before renaming.
  - **FIX-1Z-AA (Genuine Reset-Cleanup Failure Injection Seam):** In `LegacyProfileManager.reset_profile()`, modified cleanup failure injection (`_test_inject_fail_reset_cleanup_target` and `_test_inject_fail_reset_cleanup`) to intercept deletion and simulate real non-OK filesystem failure without removing the target artifact from disk. If deletion fails or any artifact remains on disk, sets `profile_status = STATUS_UNAVAILABLE`, populates `initialization_error` naming the exact lingering file(s), and returns `false`.
  - **Automated Regression Verification:** Strengthened `_test_fix_1z_w_reset_profile_resurrection_safety()` to execute an 11-step sequence verifying genuine cleanup failure against an existing `.bak.old` artifact, asserting that the file still exists, that its byte contents are unchanged, that `reset_profile()` returns `false`, that status is `STATUS_UNAVAILABLE`, and that subsequent claims are rejected fail-closed. Re-verified `_test_fix_1z_x_profile_manager_reconciliation_cases()` Case A and Case B with missing primary profiles.
- [x] **TASK-1Z.HARDENING-8:** Eighth Corrective Audit: Complete Profile Reset Artifact Coverage & In-Memory State Verification:
  - **FIX-1Z-AB (All 5 Artifacts Present Before Reset & In-Memory State Cleared):** Strengthened `_test_fix_1z_w_reset_profile_resurrection_safety()` so that all five persistence artifacts (`target_path`, `.bak`, `.bak.old`, `.tmp`, `.bak.tmp`) simultaneously exist on disk and are asserted to exist before calling `reset_profile()`. Proves that all five artifacts are deleted upon successful reset. Immediately asserts that original manager `mgr` has its in-memory state fully reset (`STATUS_NEW_PROFILE`, balances 0, empty claimed rewards, empty unlocked achievements, empty initialization error). Asserts fresh manager instance also initializes cleanly with zero state and no resurrection.
  - **FIX-1Z-AC (Achievement Reset and Stale Achievement Non-Resurrection):** Seeded original manager with a valid unlocked achievement (`"prosperity_victory"`), persisted to primary profile, and populated `.bak.old` fixture with a distinguishable, schema-valid achievement record. Verified that both original manager and fresh restart manager have `unlocked_achievements.is_empty()`, proving that achievement records are cleared from memory and not resurrected from stale backups.
  - **FIX-1Z-AD (Complete Partial Cleanup Failure Assertions):** In the cleanup failure injection scenario, created all five artifacts simultaneously on disk before calling `reset_profile()` with failure injected on `.bak.old`. Verified that `reset_profile()` returns `false`, manager status is `STATUS_UNAVAILABLE`, `initialization_error` identifies `.bak.old`, `.bak.old` survives byte-for-byte unchanged, all other four artifacts (`target_path`, `.bak`, `.tmp`, `.bak.tmp`) are successfully deleted from disk, and subsequent reward claims are rejected fail-closed.
- [x] **TASK-2A.1:** Market blueprint configuration & footprint in `EconomyConfig`:
  - Added `"market"` entry to `BLUEPRINTS` in `scripts/economy/economy_config.gd` with 3x3 footprint, cost `{wood: 25, stone: 10}`, 12.0h build time, 100 HP, 0 housing, 0 workers, empty storage.
  - Automatically derives 4 builder slots via `BuildingSystem.get_construction_worker_capacity()`.
- [x] **TASK-2A.2:** BuildingSystem Market discovery helpers & caravan docking logic:
  - Added `is_market_active()`, `get_all_active_markets()` (deterministic sort by coordinate $y \times 64 + x$ then ID), `get_active_market()`, and `get_town_hall()` in `scripts/economy/building_system.gd`.
  - Implemented `find_caravan_docking_cell(world_data)` discovering perimeter cells around active Market with fallback to Town Hall perimeter.
  - Added `grid_to_world()` alias in `scripts/utils/iso_math.gd`.
- [x] **TASK-2A.3:** WorldView presentation actor & docking visual marker:
  - Created `CaravanMarker` actor in `scripts/trade/caravan_marker.gd` with Y-sorting, citizen texture with saffron modulation (`Color(1.2, 1.05, 0.4, 1.0)`), ground-contact pivot `Vector2(-12, -30)`, and `NameLabel`.
  - Added authentic pixel art asset `assets/buildings/bld_market.png` (96x80 diamond base, 27-color palette conforming to `docs/ASSET_STYLE_GUIDE.md`).
  - Integrated dynamic marker spawning, repositioning, and removal in `scripts/world/world_view.gd` reactive to caravan arrival, departure, building completion, cancellation, demolition, and game generation.
- [x] **TASK-2A.4:** HUD BuildMenuPanel wiring & DiplomacyPanel trade location indicators:
  - Added `MarketBtn` ("⚖️ Chợ (25 Gỗ, 10 Đá)") to `scenes/ui/hud.tscn` BuildMenuPanel grid.
  - Wired `MarketBtn` in `scripts/ui/hud.gd` to initiate `"market"` ghost placement.
  - Updated `DiplomacyPanel` caravan status label to dynamically display docking location: `📍 Địa điểm giao thương: Chợ` vs `📍 Địa điểm giao thương: Tòa thị chính`.
- [x] **TASK-2A.5:** SaveManager persistence integration & legacy save backward compatibility:
  - Wired `world_view.refresh_caravan_marker()` into Step 20 of `apply_loaded_state_to_world` in `scripts/persistence/save_manager.gd`.
  - Preserved pure presentation decoupling: zero schema changes, zero disk footprint, transient re-derivation on load. Fully backwards compatible with legacy saves.
- [x] **TASK-2A.6:** Package 2A comprehensive test suite:
  - Created headless test suite `scripts/test/test_market.gd` covering 15 test cases (TC-MKT-01 to TC-MKT-15): blueprint integrity, placement validation, worker capacity, construction lifecycle, cancellation refund, deterministic selection, perimeter docking legality, Town Hall fallback, blocked perimeter fallback, demolition re-routing, multi-market resolution, atomic trade invariants, legacy save compatibility, active caravan save/load persistence, and marker idempotency.
  - Verified 15/15 tests passing (Exit Code 0).
- [x] **TASK-2A.7:** Palisade test assertion update for 12th GDD building:
  - Updated button count check in `scripts/test/test_palisade.gd` from 11 to 12 buttons to account for `MarketBtn` in `BuildMenuPanel`.

---

## Package 2B: Citizen Skill Progression & Vocational Specialization (Completed)
- [x] **TASK-2B.1:** Vocational skill data model `CitizenSkillData` (`scripts/entities/citizen_skill_data.gd`) with 6 vocations (`farming`, `woodcutting`, `mining`, `smithing`, `building`, `hauling`), XP thresholds (0, 100, 300, 600, 1000), bounded multipliers (1.00x, 1.08x, 1.16x, 1.25x, 1.35x), XP clamping [0, 1000], and Vietnamese titles.
- [x] **TASK-2B.2:** CitizenController integration: individual skill model instantiation, job-to-vocation mapping, work-rate scaling, builder contribution scaling, and hauler velocity calculation.
- [x] **TASK-2B.3:** Real-work XP attribution: +10 XP on committed production cycle, +5 XP per game-hour of active construction contribution, +10 XP on successful cargo deposit, and 0 XP for idle, eating, resting, wandering, or failed work attempts.
- [x] **TASK-2B.4:** Cross-training & career switching: role reassignment preserves 100% of accumulated XP across all vocations without decay or penalty.
- [x] **TASK-2B.5:** CitizenInspectPanel UI enhancements in `scenes/ui/hud.tscn` and `scripts/ui/hud.gd`: dynamic vocational title, level badge, XP progress bar, efficiency bonus percentage, and Level 5 maximum indicator.
- [x] **TASK-2B.6:** SaveManager backward-compatible persistence: serializing `skills` dictionary per citizen, fail-closed bounds validation, and clean fallback to Level 1 / 0 XP on legacy saves.
- [x] **TASK-2B.7:** Automated test suite `scripts/test/test_citizen_skills.gd` covering TC-SKL-01 through TC-SKL-22 with 100% pass rate (Exit Code 0).

---

## Package 2C: Surplus Treasury Conversion & Victory Settlement Integration (Completed)
- [x] **TASK-2C.1:** Core Conversion Formula & Invariants in `LegacyProfileManager`:
  - Implemented authoritative `convert_surplus_treasury(treasury_amount, stability, world_id, is_prosperity_victory)`.
  - Enforced 1,000 Gold protected reserve, 100 Gold : 1 Legacy Point conversion rate, and $\ge 80.0\%$ stability requirement.
  - Safeguarded reserve and remainder; gold deduction strictly equals `legacy_awarded * 100`.
- [x] **TASK-2C.2:** Persistent Profile Storage & Exactly-Once Semantics:
  - Added `treasury_conversions` dictionary schema to profile with serialization/deserialization and backward compatibility.
  - Linked surplus conversions to `claimed_rewards` under source `"treasury_conversion"` to conserve math invariants (`legacy_balance == lifetime_legacy_earned - lifetime_legacy_spent`).
  - Implemented transactional atomic disk saving with staging, error rollback, and recovery.
- [x] **TASK-2C.3:** Victory Settlement Flow & Lifecycle Integration in `VictoryManager`:
  - Implemented `finalize_victory_settlement(resource_mgr, stability_override)` combining base victory claim (+100) with surplus treasury conversion.
  - Added `calculate_treasury_conversion()`, `preview_treasury_conversion()`, `is_treasury_converted_or_settled()`, and `get_active_treasury_conversion_record()`.
  - Updated `generate_summary_report()` to embed treasury conversion record and status.
- [x] **TASK-2C.4:** Save/Load Persistence & Reconciliation in `SaveManager`:
  - Serialized `is_treasury_converted` and `treasury_conversion_record` inside `victory` payload.
  - Reconciled loaded state against profile records to prevent pre-settlement save re-exploitation.
- [x] **TASK-2C.5:** Victory Panel UI Integration in `hud.tscn` and `hud.gd`:
  - Added `TreasuryConversionLabel` to `VictoryPanel` displaying 6 required Vietnamese fields (original gold, preserved reserve, converted gold, legacy points, exchange rate, transaction result).
  - Dynamically updated settlement button text (`Nhận Di Sản (+100)` / `Nhận Di Sản (+140)` / `Đã Nhận Di Sản`) and feedback banners.
- [x] **TASK-2C.6:** Comprehensive Regression Test Suite:
  - Created `scripts/test/test_surplus_treasury_conversion.gd` covering all 14 authoritative requirements across 97 assertions (100% pass rate, Exit Code 0).
  - Updated `scripts/test/test_legacy_fund.gd` Scenario 14 to validate Package 2C conversion (43/43 pass, Exit Code 0).
  - Re-verified full project regression test matrix across all 12 test suites with 0 regressions.

---

## Package 2D: Cẩm Nang Trong Game & Hướng Dẫn 30 Ngày Đầu (Completed)
- [x] **TASK-2D.1:** In-Game Player Field Guide Architecture & Data Model:
  - Created standalone reusable `PlayerFieldGuide` scene (`scenes/ui/player_field_guide.tscn`) and class (`scripts/ui/player_field_guide.gd`).
  - Structured 6 comprehensive, natural Vietnamese chapters matching authoritative source code:
    - Chương A: Khởi Đầu Vương Quốc (HUD reading, clock, 24 citizens, 8 buildings, starting resources).
    - Chương B: Dân Cư & Nghề Nghiệp (Roles, idle assignment, needs, 6 Package 2B skills, 0/100/300/600/1000 XP, 1.00x-1.35x efficiency multipliers).
    - Chương C: Xây Dựng & Chuỗi Sản Xuất (Placement rules, builder labor, workplace output buffer vs central stockpile, hauler logistics, buffer saturation).
    - Chương D: Hướng Dẫn 30 Ngày Đầu Tiên (40-day year calendar, 10 days/season, Xuân 1.0x, Hè 1.2x, Thu 1.0x, Đông 0.5x [food only], 4-stage starter guide).
    - Chương E: Sự Kiện, Ngoại Giao & Quân Đội (World events, faction diplomacy, market caravans, barracks recruitment and daily upkeep).
    - Chương F: Chiến Thắng, Sụp Đổ & Di Sản (Prosperity victory hold time, collapse triggers, base victory +100 LP, Package 2C 1,000 reserve, 100:1 rate, >=80% stability, exactly-once idempotency).
- [x] **TASK-2D.2:** HUD & Pause Menu Seamless Integration:
  - Added `GuideHudBtn` (`"📖 Cẩm Nang (H)"`) on HUD for direct access during gameplay without pausing.
  - Added `GuideBtn` in `PauseMenuOverlay` between Resume and Save Game buttons.
  - Added hotkey bindings for `H` and `F1` in `hud.gd`, with `Escape` closing the guide cleanly.
  - Opening/closing causes strictly zero mutation to simulation clock, simulation speed, resources, citizens, buildings, or save state.
- [x] **TASK-2D.3:** Input Isolation & Responsive Layout:
  - Enforced `mouse_filter = Control.MOUSE_FILTER_STOP` across modal backdrop and panel, completely isolating mouse events from underlying world interaction.
  - Verified non-overlapping, fully enclosed responsive bounding across both 1280x720 and 1024x576 window sizes.
- [x] **TASK-2D.4:** Automated Test Suite:
  - Created `scripts/test/test_player_field_guide.gd` covering 9 comprehensive test groups and 119 automated assertions (100% pass rate, Exit Code 0).
- [x] **TASK-2D.5:** Live Visual Validation:
  - Captured 5 authentic live game screenshots under D3D12 hardware rendering at 1280x720 and 1024x576 (`p2d_01` through `p2d_05`).

---

## Package 2E: Autonomous Faction Conflict & Inter-Faction Warfare (Completed)
- [x] **TASK-2E.1:** Pairwise Autonomous Diplomatic Decision Engine:
  - Extended `FactionDiplomacyPlanner` (`scripts/factions/faction_diplomacy_planner.gd`) with pure, deterministic evaluation: `evaluate_pairwise_diplomatic_action()` and `evaluate_pair_diplomatic_action()`.
  - Authoritative thresholds: War declaration triggered when `opinion <= -50.0`, `military_power >= 40.0`, `stability >= 30.0`, and `power_ratio >= 0.65`.
  - Truce cooldown: 6 game days (`INTER_TRUCE_DURATION_DAYS = 6`), minimum war duration 2 days (`INTER_WAR_MIN_DURATION_DAYS = 2`), and war weariness peace trigger after 12 days (`INTER_WAR_WEARINESS_DAYS = 12`).
  - Strict anti-oscillation: peace grants $+20.0$ mutual opinion (pulling relations up to $-30.0$, far above the $-50.0$ war threshold), establishing guaranteed diplomatic stability.
- [x] **TASK-2E.2:** Pairwise Data Model & Faction Manager Integration:
  - Extended `FactionRelationData` (`scripts/factions/faction_relation_data.gd`) tracking `truce_until_day`, `war_start_day`, `casus_belli`, `war_count`, `last_battle_report`, and `is_on_truce(day)`.
  - Enhanced `FactionManager` (`scripts/factions/faction_manager.gd`) with `declare_war_between_factions()` (truce check, metadata recording), `sign_peace_between_factions()` (truce assignment, opinion boost), `execute_pairwise_diplomatic_action()`, `execute_all_pairwise_diplomacy()`, and signal `faction_pair_diplomatic_action_executed`.
  - Daily simulation step 2b evaluates and executes pairwise diplomacy before economic intent execution.
- [x] **TASK-2E.3:** Real Military Campaigns & BattleResolver Combat Resolution:
  - Enhanced `BattleCampaignManager` (`scripts/combat/battle_campaign_manager.gd`) with inter-faction campaign lifecycle: `schedule_inter_faction_campaign()`, `process_daily_inter_faction_campaigns()`, `resolve_inter_faction_campaign()`, and `cancel_inter_faction_campaigns_for_pair()`.
  - Wires `faction_pair_war_declared` to automatically schedule military campaigns (scheduled for `day + 2`) and `faction_pair_peace_signed` to cancel pending campaigns.
  - Battle resolution delegates directly to authoritative `BattleResolver.resolve_battle` with genuine force composition, combat scores, and casualty application.
  - Resource conservation: Plunder transferred strictly between defender and attacker stockpiles; zero phantom resources created.
  - Concrete world consequences: Attacker victory inflicts real siege damage to regional defender outposts via `FieldSiegeManager`, with sacking on outpost destruction; casualties deduct from military power and population.
- [x] **TASK-2E.4:** Trade Caravan Wartime Surcharge & Player Economic Impact:
  - Extended `TradeCaravan` (`scripts/trade/trade_caravan.gd`) with `is_origin_at_war` and `WARTIME_PRICE_SURCHARGE = 0.15` (+15% sell price markup when caravan originates from a faction at war, with guaranteed minimum +1 Gold markup).
  - Wired `WorldView` to dynamically detect origin faction wartime status when spawning caravans.
- [x] **TASK-2E.5:** In-Game HUD Authoritative State & Event Banners:
  - Enhanced `HUD` (`scripts/ui/hud.gd`) connecting `faction_pair_war_declared`, `faction_pair_peace_signed`, `inter_faction_campaign_scheduled`, `inter_faction_campaign_cancelled`, and `inter_faction_battle_resolved` to real-time event banners.
  - Added Section 3 to Diplomacy Panel: "⚔️ QUAN HỆ & CHIẾN SỰ GIỮA CÁC THẾ LỰC (NPC — NPC)" dynamically listing all 3 canonical pairs with color-coded status badges (`[⚔️ ĐANG CHIẾN TRANH]`, `[🕊️ ĐÌNH CHIẾN]`, `[🤝 LIÊN MINH]`, `[📜 HIỆP ƯỚC BẤT TƯƠNG XÂM]`, `[⚖️ HÒA BÌNH]`), 2-way opinion readouts, Casus Belli, war duration, pending campaign info, recent battle summaries, and player alliance warnings.
  - Added wartime surcharge warning note in Trade Caravan inspector.
- [x] **TASK-2E.6:** Fail-Closed Save/Load Schema Validation & Backward Compatibility:
  - Updated `SaveManager` (`scripts/persistence/save_manager.gd`) with schema validation for inter-faction campaigns (`pending_inter_faction_campaigns`, `processed_inter_faction_campaigns`, `recent_inter_faction_reports`, `next_inter_faction_campaign_index`), executor pairwise tracking (`last_pairwise_diplomacy_days`), and pairwise relation metadata.
  - 100% backward compatibility with legacy saves without inter-faction conflict data.
- [x] **TASK-2E.7:** Comprehensive Automated Test Suite & Live Visual Validation:
  - Created `scripts/test/test_autonomous_faction_conflict.gd` covering 14 test groups across 99 automated assertions (100% pass rate, Exit Code 0).
  - Created `scripts/test/visual_package_2e_validation.gd` capturing 3 high-fidelity 1280x720 PNG screenshots (`p2e_01` through `p2e_03`).
  - Full project regression test suite passed: 100% green across all 9 regression suites (2,304 checks/assertions passed, 0 failures, Godot 4.7 headless execution).

---

## [Phase 2 — Package 2F] In-Game Building Inspection, Workplace Management & Demolition System (Completed)

- [x] **TASK-2F.1:** Authoritative Left-Click Building Footprint Selection & Priority:
  - Implemented 5-tier authoritative left-click selection hierarchy in `WorldView._handle_left_click(cell)`: 1) Tactical military units, 2) Exact citizen on clicked cell, 3) Building occupying clicked cell via full footprint resolution, 4) Fuzzy 1-cell adjacent citizen fallback, 5) Empty ground (clears selection).
  - Accurate footprint coverage for all canonical sizes: 1x1 (Watchtower, Palisade), 2x2 (House, Farm, Woodcutter, Mine, Quarry, Barracks, Workshop), and 3x3 (Town Hall, Storehouse, Market, Research Hall).
  - Camera centering via `WorldView.focus_camera_on_building(b_id)` supporting smooth navigation to inspected structures.
- [x] **TASK-2F.2:** 2:1 Dimetric Diamond Selection Ground Highlight:
  - Created `BuildingSelectionHighlight` (`scripts/world/building_selection_highlight.gd`) extending `Node2D` rendering exact 2:1 dimetric isometric diamond ground polygon at Y-sort background layer.
  - Mathematical vertex calculation: `compute_diamond_vertices(origin, size)` generating Top `(ox - oy) * 16, (ox + oy) * 8 - 8`, Right `(ox + sx - oy) * 16, (ox + sx + oy) * 8`, Bottom `(ox + sx - (oy + sy)) * 16, (ox + sx + oy + sy) * 8 + 8`, Left `(ox - (oy + sy)) * 16, (ox + oy + sy) * 8`.
  - Translucent gold fill (`Color(1.0, 0.85, 0.2, 0.25)`), crisp 2px border polyline (`Color(1.0, 0.9, 0.3, 0.85)`), and 4 corner vertex dots.
- [x] **TASK-2F.3:** In-Game HUD BuildingInspectPanel & Live State Reflection:
  - Created responsive `BuildingInspectPanel` in `scenes/ui/hud.tscn` with title, coordinate & size readout, status badges (`Hoạt động`, `Tạm dừng`, `Đang xây dựng`, `Hư hại`), health bar, and operational action buttons.
  - Workplace Inspection Section: Output resource name, live buffer amount and capacity progress bar, saturation badges (`Bình thường` <80%, `Cảnh báo` >=80%, `Tắc nghẽn` 100%), and dual-channel workshop display (`_smelt` and `_craft` channels).
  - Assigned Workers Roster: Displays worker name, role, status reason, and Package 2B vocational skill data (Vocation display name, Level 1–5, Title, XP progress, and % efficiency bonus). Direct click on worker jumps straight to citizen inspector.
  - Civic Buildings Section: Spec-compliant gameplay descriptions and functional stat breakdowns for all 7 civic building types (`town_hall`, `house`, `storehouse`, `barracks`, `watchtower`, `market`, `research_hall`).
- [x] **TASK-2F.4:** Construction Site Inspection & Safe Cancellation Flow:
  - Live construction inspection showing builder slots, current hours / total required hours, and live progress bar.
  - Preflight validation `BuildingSystem.can_cancel_construction(b_data, world_data, resource_mgr)`: All-or-nothing 50% refund calculation, fail-closed storage capacity check preventing resource voiding.
  - Confirmation modal `CancelBuildConfirmOverlay` displaying exact refund breakdown. Safe worker release to `IDLE`, occupancy cleanup, and building record deletion.
- [x] **TASK-2F.5:** Safe Building Demolition Flow & Storage Capacity Conservation:
  - Preflight validation `BuildingSystem.can_demolish_building(b_data, world_data, resource_mgr)`: Calculates 50% blueprint material refund, verifies storage capacity post-demolition (`cur_cap - storage_bonus - cur_stock >= refund`), and evaluates Town Hall status.
  - Implemented `ResourceManager.remove_storage_capacity(res_id, bonus)` safely clamped to `maxi(0, cur_cap - bonus)`, preventing inventory destruction.
  - Town Hall emergency collapse protection: Prominently warns player with emergency banner and modal warning; demolition triggers existing 72-hour kingdom collapse countdown.
  - Demolition execution: Atomically awards refunds, removes storage capacity, releases workers to `IDLE`, unregisters workplaces and dropoffs, removes jobs, and frees visual nodes.
- [x] **TASK-2F.6:** Operational Workplace Pause / Resume Lifecycle:
  - Added `is_paused: bool` to `WorkplaceData` and multi-channel synchronization via `WorkplaceManager.set_workplace_paused(wp_id, paused)`.
  - Production suspension: `produce_to_buffer()` immediately aborts if workplace is paused (0 production, 0 input consumption, existing buffer preserved).
  - Dynamic job executability in `JobManager`: Integrated `building_checker` and `wp_mgr.is_workplace_paused()`. Non-hauler jobs are non-executable during pause, releasing workers to `IDLE` with status `"Công trình tạm dừng hoạt động"`. Hauler jobs remain executable to clear accumulated buffers.
  - Visual feedback: Sprite modulate dims to `Color(0.7, 0.7, 0.7, 0.85)` during pause.
  - Persistence: Paused state and visual modulate survive save/load roundtrips idempotently.
- [x] **TASK-2F.7:** Comprehensive Automated Test Suite & Live Visual Validation:
  - Created `scripts/test/test_building_management.gd` with 30 comprehensive test cases (TC-BM.1 through TC-BM.30), all passing with 100% pass rate (Exit Code 0).
  - Created `scripts/test/visual_package_2f_validation.gd` capturing 4 high-fidelity PNG screenshots in `docs/visual_validation/` at 1280x720 and 1024x576 (`p2f_01` through `p2f_04`).
  - Full project regression test matrix verified across all 10 suites: 100% green, 0 failures.

---

## [Phase 2 — Package 2G] Outpost Capture & Territorial Control (Completed)

- [x] **TASK-2G.1:** Authoritative Outpost Ownership Model:
  - Extended `SiegeObjectiveActor` with authoritative ownership tracking: dynamic `owning_faction_id`, immutable founding `original_owner_id`, historical `previous_owner_id`, monotonic `capture_revision`, and transaction idempotency token `last_capture_tx_id`.
  - Added `objective_ownership_changed(obj_id, prev_owner, new_owner, tx_id)` signal on `SiegeObjectiveActor` and `outpost_ownership_changed(obj_id, prev_owner, new_owner, tx_id)` on `FieldSiegeManager`.
- [x] **TASK-2G.2:** Idempotent Ownership Transfer & Health Recovery Lifecycle:
  - Implemented `SiegeObjectiveActor.transfer_ownership(new_owner_id, tx_id)`: atomic transition with strict idempotency guarding against duplicate transaction IDs and redundant owner assignment.
  - Post-conquest recovery contract: Outposts are never permanently deleted from the world map. Upon capture, health is restored to exactly 35% of `max_health` (`round(max_health * 0.35)`), resetting `is_alive = true`, `is_captured = true`, and clearing active siege state.
  - Implemented authoritative coordinator `FieldSiegeManager.transfer_outpost_ownership(obj_id, new_owner_id, tx_id)` with owner ID validation.
- [x] **TASK-2G.3:** Visual Banner Representation & Dynamic Faction Palette:
  - Enhanced `SiegeObjectiveActor._draw()` with dynamic banner colors by faction: Royal Blue (`Color(0.2, 0.45, 0.85)`) for `"player"` with golden pole and conquest finial, Crimson Red (`Color(0.8, 0.2, 0.2)`) for `rival_military`, Amber Gold (`Color(0.85, 0.65, 0.15)`) for `rival_merchant`, and Forest Green (`Color(0.2, 0.65, 0.3)`) for `neutral_tribe`.
  - Dynamic health bar color: Player-owned outposts render green health bars (`Color(0.2, 0.8, 0.2)`), while hostile/NPC outposts render red health bars (`Color(0.8, 0.2, 0.2)`).
  - Dynamic display name: "Tiền Đồn Vương Quốc" for player-owned outposts, and "Tiền Đồn [Faction Name]" for factions.
- [x] **TASK-2G.4:** Tactical Field Siege Integration & Friendly Siege Prevention:
  - Updated `FieldSiegeManager._resolve_siege_outcome()`: on `VICTORY`, authoritatively transfers outpost ownership to `"player"` with `tx_id = "player_siege_" + siege_id`, resets defenders, and emits ownership signals.
  - Updated `FieldSiegeManager.can_launch_field_siege()`: strictly prevents launching sieges against player-owned outposts (`owning_faction_id == "player"`), and permits sieging recaptured hostile outposts.
- [x] **TASK-2G.5:** NPC-NPC Autonomous Warfare Campaign Integration & Collision Avoidance:
  - Enhanced `BattleCampaignManager.schedule_inter_faction_campaign()` and `resolve_inter_faction_campaign()`: dynamically resolves the defender faction's live regional outpost.
  - Attacker victory inflicts real siege damage ($15.0$ HP per surviving troop); if breached ($HP \le 0.0$), the outpost is sacked, transfers ownership to the attacking faction, and increments `capture_revision`.
  - Active siege collision avoidance: NPC campaigns strictly skip damaging or capturing outposts currently under active player siege (`is_under_active_siege == true`).
- [x] **TASK-2G.6:** In-Game HUD Real-Time Conquest Banners:
  - Wired `FieldSiegeManager.outpost_ownership_changed` in `WorldView` to trigger real-time HUD event banners: `"ĐÃ CHIẾM TIỀN ĐỒN!"` for player conquest and `"BIẾN ĐỘNG LÃNH THỔ!"` for NPC autonomous warfare conquests.
  - Suppressed duplicate victory event banners in `WorldView._on_field_siege_resolved()`.
- [x] **TASK-2G.7:** Fail-Closed Save/Load Schema Validation & Backward Compatibility:
  - Updated `SaveManager.validate_save_data()` with strict fail-closed validation for `original_owner_id`, `previous_owner_id`, `capture_revision`, and `last_capture_tx_id`.
  - Backward compatibility: Legacy save files deserialize cleanly with `original_owner_id = owning_faction_id`, `previous_owner_id = ""`, `capture_revision = 0`, and `last_capture_tx_id = ""`.
- [x] **TASK-2G.8:** Dedicated Automated Test Suite & Full Regression Matrix Verification:
  - Created `scripts/test/test_outpost_territorial_control.gd` covering 8 mandatory test groups and 108 assertions (100% pass rate, Exit Code 0).
  - Executed all 17 regression test suites cleanly with 0 failures (Exit Code 0 across all suites).
  - Executed Godot 4.7 editor headless parse check cleanly with 0 errors.
