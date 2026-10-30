# KINGDOMS UNBOUND â€” Master Test Plan & Verification Strategy

## Document Overview
- **Status:** Active (Phase 0 Baseline)
- **Engine:** Godot 4.7.stable (Windows x64)
- **Authority:** Operationalizes `MASTER_PROMPT.md` Section "Automated Testing and Runtime QA".
- **Verification Policy:**
  - Never claim a test passed unless actually executed.
  - Differentiate `Implemented`, `Headless-Script-Passed`, `Runtime-Tested`, and `Visually-Reviewed`.

---

## 1. Test Harness & Execution Methods

### 1.1 Headless Command-Line Validation (Deterministic Fallback)
Headless commands execute directly in PowerShell using the verified Godot 4.7 console executable:

1. **Project Syntax & Asset Import Scan:**
   ```powershell
   & "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "E:\KINGDOMS UNBOUND\kingdoms-unbound" --quit
   ```
2. **Execute Headless Test Script:**
   ```powershell
   & "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "E:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/<test_script>.gd
   ```

### 1.2 Godot MCP Live Inspection & Runtime Validation
When Godot Editor is running with the MCP plugin:
- `diagnose_connection`: live connection status check.
- `get_errors`: fetch active runtime error logs.
- `take_screenshot`: capture rendering output for visual inspection.
- `run_scene` / `stop_scene`: launch scenes and test interactions.

---

## 2. Test Suites by Phase

### Phase 0: Project Baseline & Environment
- **TC-0.1: Project Import & Parse Check**
  - *Method:* Headless editor launch with `--quit`.
  - *Acceptance Criteria:* Exit code 0, 0 script parse errors, 0 corrupt asset errors.
  - *Status:* **PASSED** (2026-10-12, verified via task-46/console check).
- **TC-0.2: MCP WebSocket Live Bridge Check**
  - *Method:* MCP `get_godot_status` and `diagnose_connection`.
  - *Acceptance Criteria:* `healthy: true`, `connected: true`, target path matches workspace root.
  - *Status:* **PASSED** (2026-10-12, verified live on port 6505).

### Phase 1: Coordinate Transformation & Visual-Validation Gate
- **TC-1.1: Isometric Coordinate Forward/Inverse Transformation**
  - *Script:* `res://scripts/test/test_coordinates.gd`
  - *Acceptance Criteria:* All 13 reference points (tile centers, interior offsets, vertices, boundaries) map identically forward and backward between `Vector2i` and local pixel space.
  - *Status:* Ready for Phase 1.
- **TC-1.2: Seed Reproducibility Test**
  - *Script:* `res://scripts/test/test_world_gen.gd`
  - *Acceptance Criteria:* Two generation runs with seed `12345` produce identical terrain elevation and starter building placements.
  - *Status:* Pending Phase 1.
- **TC-1.3: Visual-Validation Gate Runtime Scene**
  - *Scene:* `res://scenes/test/visual_validation_test.tscn`
  - *Acceptance Criteria:* Demonstrates 32Ã—16 diamond terrain, multi-tile building with visible roof/facade, isometric tree props, 1 moving citizen with feet pivot at $(12, 30)$, diamond hover highlight, and flawless Y-sorting behind/in front of structures.
  - *Status:* Pending Phase 1.

### Phase 2: Authoritative Resource Ledger & Building Placement
- **TC-2.1: Resource Ledger Conservation & Reservations**
  - *Acceptance Criteria:* Resources cannot be double-spent; reservations lock stock; cancelling releases stock.
  - *Status:* **PASSED** (2026-10-12, verified in `test_economy.gd`).
- **TC-2.2: Building Cost Deductions & Invalid Placement Rejection**
  - *Acceptance Criteria:* Placement on occupied or out-of-bounds tiles rejected; costs deducted exactly once.
  - *Status:* **PASSED** (2026-10-12, verified in `test_economy.gd`).

### Phase 3: Citizens & Grid Navigation
- **TC-3.1: A* Pathfinding Walkability & Blocked Target Recovery**
  - *Acceptance Criteria:* Citizens navigate around obstacles; unreachable targets fail gracefully without infinite loop.
  - *Status:* **PASSED** (2026-10-12, verified in `test_citizens.gd`).
- **TC-3.2: 24 Citizen Spawn & Job Distribution**
  - *Acceptance Criteria:* Exactly 24 unique citizen IDs; 5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle.
  - *Status:* **PASSED** (2026-10-12, verified in `test_citizens.gd`).

### Phase 4: Logistics & Automation Loop
- **TC-4.1: Physical Hauling vs Teleportation**
  - *Acceptance Criteria:* Produced goods remain in workplace buffer until hauled; storehouse updates only on deposit.
  - *Status:* **PASSED** (2026-10-12, verified in `test_logistics.gd`).
- **TC-4.2: Winter Food Deficit & Starvation Escalation**
  - *Acceptance Criteria:* Farm output halves in winter; 0 food does not instantly kill; health drops 5%/day.
  - *Status:* **PASSED** (2026-10-12, verified in `test_logistics.gd`).

### Phase 5: Research & Events
- **TC-5.1: Research Pause Safety & Unlock Persistence**
  - *Acceptance Criteria:* Pausing halts research; completed tech applies bonuses to all workers.
  - *Status:* Pending Phase 5.
- **TC-5.2: Fog of War Tile States & POI Single Claim**
  - *Acceptance Criteria:* POI rewards cannot be claimed more than once.
  - *Status:* Pending Phase 5.

### Phase 6: Factions & Battles
- **TC-6.1: Deterministic Battle Resolver**
  - *Acceptance Criteria:* Identical inputs produce identical casualty and morale outcomes.
  - *Status:* **PASS** (100% deterministic reproducibility across identical runs, fort and terrain defense verified in `test_factions_and_battles.gd`).
- **TC-6.2: Trade Atomic Transaction**
  - *Acceptance Criteria:* Trades succeed all-or-nothing; cannot generate duplicate currency.
  - *Status:* **PASS** (Atomic transactions, finite inventory, price asymmetry, zero duplication verified in `test_factions_and_battles.gd`).

### Phase 7: Victory & Collapse
- **TC-7.1: Immigration Pacing & Condition Gating**
  - *Acceptance Criteria:* Evaluates housing, food, stability, and morale gating; expands population to 30 with unique IDs and Vietnamese names.
  - *Status:* **PASS** (Condition gating and wave admission verified in `test_victory_and_collapse.gd`).
- **TC-7.2: Prosperity Victory 5-Day Hold Duration & Reset**
  - *Acceptance Criteria:* Victory triggers only after 120 continuous game-hours satisfying all conditions; timer resets on lapse; duplicate legacy claims prevented.
  - *Status:* **PASS** (Continuous hold, reset on metric lapse, clean victory trigger at hour 120, and single-claim legacy protection verified in `test_victory_and_collapse.gd`).
- **TC-7.3: Deterministic Collapse Grace Period & Explanatory Summary**
  - *Acceptance Criteria:* Extinction triggers immediately at pop 0; Town Hall ruin triggers at 72 hours; Prolonged Anarchy triggers at 72 hours; summary report outputs primary cause.
  - *Status:* **PASS** (Extinction, 72-hour town hall ruin, 72-hour anarchy, and summary report verified in `test_victory_and_collapse.gd`).

### Phase 8: Save / Load Integrity
- **TC-8.1: Save $\to$ Load $\to$ Save Equivalence**
  - *Acceptance Criteria:* State before save equals state after reload across all entities and inventories.
  - *Status:* Pending Phase 8.
- **TC-8.2: Corrupt File Handling**
  - *Acceptance Criteria:* Corrupted JSON displays error dialog and preserves previous good backup.
  - *Status:* Pending Phase 8.

### Phase 9: Performance Stress
- **TC-9.1: 100 Citizen Simulation Stress Test**
  - *Acceptance Criteria:* Simulation maintains $\ge 60$ FPS at $1\times$ and $3\times$ speed with 100 active pathfinding citizens.
  - *Status:* Pending Phase 9.

---

## 3. Test Execution Log
| Date | Test Case | Target | Result | Evidence / Notes |
|---|---|---|---|---|
| 2026-10-12 | TC-0.1 | Engine Launch & Scan | **PASS** | Exit code 0, 0 errors after adding `docs/.gdignore` |
| 2026-10-12 | TC-0.2 | MCP Bridge Connection | **PASS** | `diagnose_connection` healthy, port 6505 live |
| 2026-10-12 | TC-1.1 | Coordinate Forward/Inverse Transform | **PASS** | All 13 cases passed in `test_coordinates.gd` |
| 2026-10-12 | TC-1.2 | Deterministic Seeded World Generation | **PASS** | 100% identical 64Ã—64 grid across runs in `test_world_gen.gd` |
| 2026-10-12 | TC-1.3 | Visual-Validation Gate Scene | **PASS** | `visual_validation_test.tscn` passed headless & live screenshot 3162 inspected |
| 2026-10-12 | TC-1.4 | TimeManager Clock & Pause Safety | **PASS** | Speeds 0â€“3, pause safety, seasonal modifiers passed in `test_time_manager.gd` |
| 2026-10-12 | TC-2.1 | Resource Conservation & Atomic Reservations | **PASS** | Atomic cost locks, storage caps, double-spend prevention verified in `test_economy.gd` |
| 2026-10-12 | TC-2.2 | Building Placement & Single-Cost Deduction | **PASS** | Footprint occupancy, water rejection, collision checks verified in `test_economy.gd` |
| 2026-10-12 | TC-3.1 | A* Pathfinding Walkability & Blocked Target | **PASS** | Obstacle avoidance & unreachable handling verified in `test_citizens.gd` |
| 2026-10-12 | TC-3.2 | 24 Citizen Spawn & Job Allocation | **PASS** | Exactly 24 citizens, starter roles, unique IDs verified in `test_citizens.gd` |
| 2026-10-12 | TC-4.1 | Physical Hauling Loop vs Teleportation | **PASS** | Workplace buffers & physical hauler loop verified in `test_logistics.gd` |
| 2026-10-12 | TC-4.2 | Seasonal Modifiers & Starvation Escalation | **PASS** | Summer 1.2x vs Winter 0.5x & non-instant health decay verified in `test_logistics.gd` |
| 2026-10-12 | TC-4.3 | Priority Automation Rules & Execution Budget | **PASS** | Emergency food boosts & 10-check limit verified in `test_logistics.gd` |
| 2026-10-12 | TC-5.1 | Tech Tree Prerequisites & Deductions | **PASS** | 4 branches, 10 techs, atomic cost lock, single project verified in `test_research_and_exploration.gd` |
| 2026-10-12 | TC-5.2 | Fog of War & POI Exploration Rewards | **PASS** | 3-state degradation, POI reveal, and single-claim lock verified in `test_research_and_exploration.gd` |
| 2026-10-12 | TC-5.3 | World Events & Cooldown Intervals | **PASS** | Event trigger, resource grants, cooldown intervals verified in `test_research_and_exploration.gd` |
| 2026-10-12 | TC-6.1 | Faction Treaties & Atomic Trade Conservation | **PASS** | NAP gating, war breaks, atomic caravan buy/sell, zero dupe verified in `test_factions_and_battles.gd` |
| 2026-10-12 | TC-6.2 | Deterministic Battle Resolver & Explanations | **PASS** | Deterministic reproducibility, plunder spoils, Tier 3 fort defense verified in `test_factions_and_battles.gd` |
| 2026-10-12 | TC-7.1 | Immigration Pacing & Gating | **PASS** | Rejection on full housing, food, stability, morale; wave admitted; unique IDs & names in `test_victory_and_collapse.gd` |
| 2026-10-12 | TC-7.2 | 5-Day Prosperity Victory Hold & Reset | **PASS** | 100h hold without early win; reset on lapse; 120h continuous win; duplicate claim prevention in `test_victory_and_collapse.gd` |
| 2026-10-12 | TC-7.3 | Deterministic Collapse Triggers & Summaries | **PASS** | Pop 0 extinction; 72h town hall ruin; 72h anarchy; summary report with cause in `test_victory_and_collapse.gd` |
| 2026-10-12 | TC-8.1 | Saveâ†’Loadâ†’Save Canonical Equivalence | **PASS** | 24 citizens, 8 buildings, resources, research, victory, fog_of_war 100% preserved across roundtrip in `test_save_load.gd` |
| 2026-10-12 | TC-8.2 | Corruption Handling & Backup Recovery | **PASS** | Bad schema rejected; missing section rejected; malformed JSON rejected; .bak fallback succeeded in `test_save_load.gd` |
| 2026-10-12 | TC-8.3 | UI Save/Load & Menu Integration | **PASS** | Pause menu opened; HUD save button saved and displayed "âœ…" feedback; HUD load button restored world state (gold verify); MainMenu LoadWorldBtn enabled in `test_save_load.gd` |
| 2026-10-12 | TC-9.1 | 100 Citizen Simulation Stress Test | **PASS** | 145.5 FPS at 1x (6.87 ms), 144.9 FPS at 3x (6.90 ms); 72 continuous simulation hours executed in 238.65 ms in `test_stress_100_citizens.gd` |
| 2026-10-12 | TC-9.2 | Procedural Audio Synthesis Subsystem | **PASS** | 8 16-bit PCM streams, polyphonic pool, volume curves, mute toggle verified in `test_audio.gd` |
| 2026-10-18 | TC-BR.1 | Barracks Blueprint Validation & Configuration | **PASS** | Footprint 3x3, cost 25W/20S/5M, 2 guards verified in `test_barracks.gd` |
| 2026-10-18 | TC-BR.2 | Barracks Placement, Bounds, Water & Deductions | **PASS** | Placement validity, rejection coverage (zero deduction), 9-cell occupancy verified in `test_barracks.gd` |
| 2026-10-18 | TC-BR.3 | is_barracks_active Detection & State Checks | **PASS** | Active only detection across states (active, paused, damaged, under_construction, planned, destroyed) and building ID filtering in `test_barracks.gd` |
| 2026-10-18 | TC-BR.4 | Guard Role Gating at UI & Controller Layers | **PASS** | Fail-closed role gating and annotation verified in `test_barracks.gd` |
| 2026-10-18 | TC-BR.5 | Deterministic Guard Duty Loop & Perimeter Posts | **PASS** | Real TimeManager pause test, need decay (+4.167H/+4.0F), hunger>=70 release, constrained 1-post and overlapping layout isolation in `test_barracks.gd` |
| 2026-10-18 | TC-BR.6 | Multi-Barracks Segregation & Downtime Behavior | **PASS** | Fail-closed guard job validation (empty building ID, missing checker, 0-arg global filter rejection), multi-barracks duty tracking, individual duty release on building downtime, role retention in `test_barracks.gd` |
| 2026-10-18 | TC-BR.7 | WorldView Lifecycle & Save/Load Persistence | **PASS** | Placement, double-load idempotency, inactive barracks load test, legacy save compatibility, and zero resource deduction on load verified in `test_barracks.gd` |
| 2026-10-18 | TC-CON.1 | Blueprint Verification & Placement Lifecycle | **PASS** | Positive construction hours, storehouse capacity withheld while under construction in `test_construction.gd` |
| 2026-10-18 | TC-CON.2 | Construction Jobs & Concurrent Capacity | **PASS** | Idempotent job registration (double-call safe), Subchecks A-D (stale cell outside perimeter rejected, duplicate cell deduplication, worker safety, strict idempotency, overlapping prefix isolation), builder `request_job`, cleanup isolation in `test_construction.gd` |
| 2026-10-18 | TC-CON.3 | Builder Work Loop, Scaling & Progress | **PASS** | Active builders advance progress, genuine TimeManager pause halts work, game speed scaling (1x, 2x, 3x), zero progress when idle in `test_construction.gd` |
| 2026-10-18 | TC-CON.4 | Strict Completion Threshold & Operational Activation | **PASS** | 0% and partial progress completion rejected, negative delta rejected, storehouse storage effects fail-closed on missing RM, non-duplicating storage in `test_construction.gd` |
| 2026-10-18 | TC-CON.5 | Cancellation Policy, 50% Refund & Storage Capacity | **PASS** | All-or-nothing storage capacity check, prefix isolation (`bld_house_28_28` vs `bld_house_28_280`), exact 50% refund, double cancellation rejected in `test_construction.gd` |
| 2026-10-18 | TC-CON.6 | Save/Load Persistence, Hover & Malformed Save Rejection | **PASS** | Footprint mismatch (3x3 house) rejected, fractional coords/dims rejected, legacy saves omitting size fields validated cleanly from blueprint in `test_construction.gd` |

### Phase 8: Save/Load Persistence
- **TC-8.1: Save â†’ Load â†’ Save Canonical Equivalence**
  - *Script:* `res://scripts/test/test_save_load.gd`
  - *Acceptance Criteria:* Roundtrip from live world through save file and back preserves 100% canonical state; no entity or building duplication.
  - *Status:* **PASSED** (2026-10-12, Exit Code 0).
- **TC-8.2: Corruption Handling & Backup Recovery**
  - *Script:* `res://scripts/test/test_save_load.gd`
  - *Acceptance Criteria:* Incompatible schema, missing sections, and malformed JSON all rejected gracefully; automatic `.bak` fallback works.
  - *Status:* **PASSED** (2026-10-12, Exit Code 0).
- **TC-8.3: UI Save/Load & Menu Integration**
  - *Script:* `res://scripts/test/test_save_load.gd`
  - *Acceptance Criteria:* HUD save button writes file and shows success; HUD load button restores world state; MainMenu LoadWorldBtn enabled when save exists.
  - *Status:* **PASSED** (2026-10-12, Exit Code 0).
- **TC-8.9: Package 1X Schema Validation (Enemy Military & Field Siege)**
  - *Script:* `res://scripts/test/test_save_load.gd`
  - *Acceptance Criteria:* Deep validation rejects malformed enemy military records (bad ID, coords, bounds, paths) and malformed field siege records (bad IDs, durability, non-existent objective references) fail closed, while accepting valid schema version 1 structures.
  - *Status:* **PASSED** (2026-10-29, Exit Code 0).
- **TC-8.10: Package 1X WorldView End-to-End Persistence & Double Load Idempotency**
  - *Script:* `res://scripts/test/test_save_load.gd`
  - *Acceptance Criteria:* Full live world persistence roundtrip saves and restores outposts, enemy tactical forces, and active sieges; second consecutive load preserves 100% identical state with zero node duplication.
  - *Status:* **PASSED** (2026-10-29, Exit Code 0).

### Phase 9: Performance Stress & Polish
- **TC-9.1: 100 Citizen Simulation Stress Test**
  - *Script:* `res://scripts/test/test_stress_100_citizens.gd`
  - *Acceptance Criteria:* Simulation maintains $\ge 60$ FPS at $1\times$ and $3\times$ speed with 100 active pathfinding citizens.
  - *Status:* **PASSED** (2026-10-12, Exit Code 0: 145.5 FPS at 1x, 144.9 FPS at 3x).
- **TC-9.2: Procedural Audio Synthesis Subsystem**
  - *Script:* `res://scripts/test/test_audio.gd`
  - *Acceptance Criteria:* All 8 procedural sound streams generate and play cleanly without external file dependencies.
  - *Status:* **PASSED** (2026-10-12, Exit Code 0: 5/5 subtests passed).

### Package 1G: Barracks & Guard Integration (Final Hardening)
- **TC-BR.1 to TC-BR.7: Barracks & Guard Duty Suite**
  - *Script:* `res://scripts/test/test_barracks.gd`
  - *Acceptance Criteria:* Authoritative blueprint, rejection coverage with 0 resource deductions, comprehensive active-state & building-ID filtering, fail-closed role gating, fail-closed guard job executability (rejecting empty building IDs, 0-arg global filters, and inactive buildings), genuine TimeManager pause verification, working need decay (+4.167H/+4.0F), constrained layout & overlapping perimeter deduplication, multi-barracks duty segregation, double-load idempotency, inactive barracks load test, legacy save compatibility.
  - *Status:* **PASSED** (2026-10-18, Exit Code 0: 7/7 tests passed).

### Package 1H: Builder & Construction Lifecycle (Final Hardening, Review Fix & Assignment Safety)
- **TC-CON.1 to TC-CON.6: Construction Lifecycle Suite**
  - *Script:* `res://scripts/test/test_construction.gd`
  - *Acceptance Criteria:* Positive construction_hours across blueprints, storehouse capacity withheld while under construction, atomic cost reservation/deduction, concurrent builder job capacities (1x1: 2, 2x2: 3, 3x3: 4) bounded by perimeter cells, idempotent construction job registration with strict perimeter containment check, duplicate target cell deduplication with active worker preservation and safe release to IDLE without leaving orphaned job references, Subchecks Aâ€“D (stale cell cleanup, duplicate cell deduplication, worker safety, strict idempotency, overlapping prefix isolation), Subchecks Eâ€“G (preserving unrelated valid assignments when invalid job has worker_id pointing to that citizen, safely clearing actual stale assignments to IDLE with empty path, and exact construction project ownership preserving delimited prefix jobs such as bld_house_15_15_annex), active builder progress accumulation (`delta_hours` per working builder), genuine TimeManager pause safety (0x halts progress, 1x/2x/3x scale properly), strict completion threshold (`progress >= hours - 0.001` required; premature 0% or partial completion refused without side effects), negative progress delta rejected, fail-closed storage capacity application on completion (refusing activation if required ResourceManager is missing, non-duplicating storage bonus), prefix-isolated job matching (`JobManager.job_matches_building`), all-or-nothing storage capacity validation on cancellation refund (preserving building if storage cannot fit refund), exact 50% refund, blueprint footprint validation in `SaveManager.validate_save_data()` (rejecting mismatched footprints such as 3x3 houses and fractional coordinates/dimensions; resolving legacy saves omitting size fields), double load idempotency, legacy save compatibility.
  - *Status:* **PASSED** (2026-10-18, Exit Code 0: 6/6 tests passed).

### Package 1I: Palisade & Fortification System
- **TC-PA.1: Blueprint Verification & Placement Legality**
  - *Script:* `res://scripts/test/test_palisade.gd`
  - *Acceptance Criteria:* Blueprint `palisade` has 1x1 footprint, 4 Wood + 2 Stone cost, 3.0h construction time, 0 workers, empty storage, no production jobs. Placement creates site in `under_construction` state with initial progress 0.0h, marks 1x1 cell occupied immediately, and deducts 4W+2S atomically. Placement on water, occupied cell, out of bounds, or with insufficient funds rejected fail-closed.
  - *Status:* **PASSED** (2026-10-18, Exit Code 0).
- **TC-PA.2: Construction Lifecycle & Worker Capacity**
  - *Script:* `res://scripts/test/test_palisade.gd`
  - *Acceptance Criteria:* Worker capacity for 1x1 palisade is strictly 2. Visual node instantiates with amber modulate `Color(0.8, 0.7, 0.5, 0.7)`. Exactly 2 builder jobs registered. Premature completion rejected at 0% and 50% progress. Negative delta safely rejected. Legit completion transitions state to `active`, resets modulate to `Color(1, 1, 1, 1)`, and cleans up builder jobs idempotently.
  - *Status:* **PASSED** (2026-10-18, Exit Code 0).
- **TC-PA.3: Cancellation Policy & Resource Refund**
  - *Script:* `res://scripts/test/test_palisade.gd`
  - *Acceptance Criteria:* Missing ResourceManager fails closed. Insufficient storage space rejects cancellation safely. Exact 50% refund (+2 Wood, +1 Stone) credited atomically. Occupancy cleared, jobs removed, visual node queued for deletion. Overlapping prefix building preserved. Re-cancellation safely rejected.
  - *Status:* **PASSED** (2026-10-18, Exit Code 0).
- **TC-PA.4: Navigation Grid Obstacle & Walkability**
  - *Script:* `res://scripts/test/test_palisade.gd`
  - *Acceptance Criteria:* Palisade cell is strictly unwalkable in `GridNavigation.is_walkable()`. Pathfinding successfully calculates collision-free bypass around palisade obstacle.
  - *Status:* **PASSED** (2026-10-18, Exit Code 0).
- **TC-PA.5: Save/Load Persistence & Reconstitution**
  - *Script:* `res://scripts/test/test_palisade.gd`
  - *Acceptance Criteria:* World state saved and restored with active and under-construction palisades. Zero resource deduction on load. Construction progress and hours perfectly restored. Zero visual node duplication. Builder jobs cleanly reconstructed for under-construction palisades.
  - *Status:* **PASSED** (2026-10-18, Exit Code 0).
- **TC-PA.6: Settlement Fortification & Battle Integration**
  - *Script:* `res://scripts/test/test_palisade.gd`
  - *Acceptance Criteria:* `BuildingSystem.calculate_fortification_level` and `BattleResolver.calculate_settlement_fortification_level` strictly ignore under-construction and damaged palisades. Duplicate records at same cell deduplicated. Threshold scaling verified (0 palisades: 0, 1–4: 1, 5–9: 2, 10+: 3). BattleResolver applies correct fortification combat score bonus (+90% for level 3).
  - *Status:* **PASSED** (2026-10-18, Exit Code 0).
- **TC-PA.7: HUD Integration, BuildMenuPanel Layout & Visual Presentation**
  - *Script:* `res://scripts/test/test_palisade.gd`
  - *Acceptance Criteria:* All 11 building buttons present in `GridContainer`. `BuildMenuPanel` height (410.0 px) accommodates combined minimum content size (378.0 px) with zero clipping. `BuildMenuPanel` positioned above `BottomBar` with 8.0 px clearance (zero overlap) and horizontally centered on viewport. Final grid row (`PalisadeBtn`) and `CloseBuildBtn` lie strictly within panel boundaries. `CloseBuildBtn` cleanly dismisses build menu. Pressing `PalisadeBtn` initiates placement mode, displaying ghost preview with correct texture and offset `Vector2(-16.0, -28.0)`. Canceling hides ghost cleanly. WorldView Vietnamese display name verified: `"Tường Rào Phòng Ngự (1x1)"`.
  - *Status:* **PASSED** (2026-10-19, Exit Code 0: Subchecks A–G passed).

### Package 1J: Settlement Battle & Fortification Integration
- **TC-BF.1 to TC-BF.12: Settlement Battle & Fortification Verification Suite**
  - *Script:* `res://scripts/test/test_battle_fortification.gd`
  - *Acceptance Criteria:*
    - **TC-BF.1 (Zero Palisades):** Settlement with 0 palisades resolves at fortification level 0 (bonus 1.0, `has_settlement_context == true`).
    - **TC-BF.2 (Single Active Palisade):** 1 active palisade produces fortification level 1 (bonus 1.30, +30%).
    - **TC-BF.3 (Threshold Boundaries):** Boundary steps: 4 palisades (level 1, bonus 1.30), 5 palisades (level 2, bonus 1.60), 9 palisades (level 2, bonus 1.60), 10 palisades (level 3, bonus 1.90), 15 palisades (clamped level 3, bonus 1.90).
    - **TC-BF.4 (Duplicate Cell Deduplication):** Duplicate active palisades placed at identical cell deduplicated to 1 unique cell (level 1).
    - **TC-BF.5 (State Filtering):** Non-active palisades (`under_construction`, `damaged`, `paused`, `destroyed`) do not contribute.
    - **TC-BF.6 (Authoritative Override):** Pre-existing caller-supplied `fortification_level` (e.g. fabricated level 3 or omitted) is strictly overridden by authoritative calculation from `WorldData`.
    - **TC-BF.7 (Attacker Score Independence):** Attacker force never receives defender's fortification bonus; attacker score strictly identical across fortification tiers.
    - **TC-BF.8 (Caller Immutability):** Caller dictionaries `attacker_force` and `defender_force` (including nested `resources`) are not mutated by battle resolution.
    - **TC-BF.9 (Determinism):** Identical input and seed produce 100% deterministic reports (victor, casualties, scores, details).
    - **TC-BF.10 (Formula Verification):** Report details reflect the exact multi-factor formula `float(troops) * equip_bonus * morale_factor * fort_bonus * terrain`.
    - **TC-BF.11 (Fail-Closed Handling):** Invalid or null `defender_world_data` fails closed (`has_settlement_context == false`, level 0, bonus 1.0).
    - **TC-BF.12 (Backward Compatibility):** Existing direct calls to `BattleResolver.resolve_battle()` remain fully operational and compatible.


### Package 1K: Live War & Settlement Defense Battle Loop
- **TC-LB.1 to TC-LB.19: Live Battle Loop Verification Suite**
  - *Script:* `res://scripts/test/test_live_battle_loop.gd`
  - *Acceptance Criteria:*
    - **TC-LB.1 (War Declaration Schedules Raid with 3-Day Delay):** Declaring war schedules raid at current day + 3; raises `raid_scheduled` signal; pending raid visible in queries and HUD.
    - **TC-LB.2 (Peace Declaration Cancels Pending Raid):** Signing peace immediately removes pending raid; raises `raid_cancelled` signal; zero battles triggered while at peace.
    - **TC-LB.3 (Attacking Force Derivation from Faction Military Power):** Enemy force converts `military_power` into troops (`clampi(roundi(military_power / 30.0), 1, 20)`), equipment tier, and morale based on stability.
    - **TC-LB.4 (Defending Force Guard Selection & Barracks Gate):** Living citizens with role `"guard"` assemble as defenders; if Barracks is absent or not active (`is_barracks_active(world_data) == false`), defending force strictly has 0 troops regardless of guard count.
    - **TC-LB.5 (Authoritative Fortification Integration):** `resolve_settlement_battle` automatically applies settlement palisade fortification level to defender combat score.
    - **TC-LB.6 (Zero-Defender / Unopposed Raid Resolution):** With 0 guards or inactive Barracks, attacker wins unopposed with 0 casualties on both sides; 20% resource plunder applied cleanly without divide-by-zero or crash.
    - **TC-LB.7 (Zero-Attacker Edge Case Safety):** Edge case with 0 attacking troops resolves cleanly without crash or fictitious casualties.
    - **TC-LB.8 (Zero vs Zero Stalemate Safety):** 0 vs 0 troops resolves cleanly as stalemate with 0 casualties.
    - **TC-LB.9 (Casualty Bounds Clamping):** Casualties never exceed force size (`clampi(..., 1, troops)`); no underflow or overflow.
    - **TC-LB.10 (Authoritative Guard Casualty Lifecycle & Job Release):** Defending casualties selected deterministically, killed via `citizen_died` signal with active job release, and removed from citizen registry.
    - **TC-LB.11 (Enemy Military Power Reduction & Floor):** Hostile faction military power reduced by $30.0 \times \text{casualties}$, clamped to floor 0.0 without going negative.
    - **TC-LB.12 (Resource Plunder Accounting & Reserved Stock Protection):** On attacker victory, up to 20% of food, wood, stone, and iron plundered; reserved stock is strictly protected and never touched; storage and resources stay valid.
    - **TC-LB.13 (Recurring Raid Scheduling & War Exhaustion):** While at war with `military_power > 0`, completing a raid schedules the next raid for `day + 5`; when `military_power <= 0`, no further raid is scheduled.
    - **TC-LB.14 (Save/Load Persistence, Replay Protection & Idempotency):** Battle campaign state (`pending_raids`, `processed_raids`, `raid_sequence`) serializes and restores cleanly across save/load; duplicate or replayed raids rejected; legacy saves without `"battle_campaign"` load safely with defaults.
    - **TC-LB.15 (Overdue Raid Processing & Current Day Scheduling):** Overdue raid scheduled for Day 5 processed at Day 20 resolves on actual day 20 (preserving scheduled day 5 in context), schedules next raid for Day 25 (20 + 5, not 5 + 5 = 10), and cannot resolve again on Day 20.
    - **TC-LB.16 (Transactional Plunder, Reservation Failure & In-Flight Guard):** Plunder calculated from available stock only, protecting reserved stock; simulated reservation failure fails closed with 0 plunder reported and 0 deducted; in-flight re-entrancy guard rejects concurrent calls and processed set rejects replay; incomplete non-transactional `ResourceManager` lacking `reserve_cost`/`commit_cost` strictly fails closed with 0 plundered and 0 deducted.
    - **TC-LB.17 (Accurate Battle-Death vs Starvation Event Notifications):** Combat casualties emit `citizen_died` and trigger `Chiến Binh Tử Trận` with payload `cause == "combat"`; civilian starvation deaths retain `Tang Lễ Vương Quốc` with payload `cause == "starvation_or_exhaustion"`; duplicate death calls for already deceased citizens are ignored idempotently without extra events or population changes; non-existent citizen IDs produce zero events.
    - **TC-LB.18 (Real Daily Scheduling via TimeManager Signals):** End-to-end integration with `TimeManager` clock: war declared Day 10 schedules Day 13; advancing Day 11 and 12 causes zero premature resolution; advancing to Day 13 resolves raid on tick and schedules Day 18; hourly advance causes zero duplicates; signing peace on Day 14 cancels pending raid and stays canceled through Day 20.
    - **TC-LB.19 (Legacy Save Campaign State Reset & Execution Prevention):** Loading a legacy save lacking `"battle_campaign"` or empty actively calls `campaign_mgr.deserialize({})`, purging pending raids, processed IDs, and in-flight guards; advancing time to the previously scheduled raid day triggers zero raids; subsequent world serialization produces clean canonical campaign schema with empty collections.
  - *Status:* **PASSED** (2026-10-19, Exit Code 0: 19/19 tests passed).

### Package 1L: Player Army Recruitment & Upkeep (Final Review Fix & Integration Hardening)
- **TC-ARMY.1 to TC-ARMY.32: Player Army Recruitment, Upkeep, Garrison Defense & Integration Suite**
  - *Script:* `res://scripts/test/test_player_army.gd`
  - *Acceptance Criteria:*
    - **TC-ARMY.1 to TC-ARMY.5 (Capacity & Barracks Gating):** Initial state begins with 0 soldiers, 0 capacity (when no barracks exist), supplied status (`is_supplied == true`), and `last_upkeep_day == -1`. Recruitment is rejected fail-closed with 0 barracks; under-construction barracks contribute strictly 0 capacity; 1 active barracks allows recruitment up to 5 soldiers; 2 active barracks allows recruitment up to 10 soldiers.
    - **TC-ARMY.6 to TC-ARMY.13 (Atomic Recruitment Transactions & Non-Citizen Design):** Atomic reservation and commit of 20 Gold, 2 Metal, and 5 Food per soldier. Insufficient gold, metal, or food fails closed with zero resources deducted. Zero and negative recruitment counts (-1, -5) rejected safely. Over-capacity recruitment fails closed. Abstract recruited soldiers do not modify civilian citizen lists or inflate population. Repeated recruitments up to capacity succeed; subsequent recruitments beyond capacity fail closed.
    - **TC-ARMY.14 to TC-ARMY.22 (Daily Food Upkeep & Morale Scaling):** Upkeep consumes 1 Food per soldier on daily simulation ticks. Same-day multiple upkeep invocations are strictly idempotent. Zero-soldier army incurs 0 food upkeep. Insufficient food marks army unsupplied (`is_supplied = false`) without deleting soldiers or partially deducting food. Supplied army contributes 70.0 combat morale; unsupplied army contributes 45.0 morale. Replenishing food on subsequent day restores supplied status and 70.0 morale. TimeManager pause and speed changes (1x, 2x, 3x) cause zero duplicate or premature upkeep.
    - **TC-ARMY.23 to TC-ARMY.28 (Defending Force Integration, Casualty Priority & Real Death Lifecycle):** Defending garrison combines recruited army units + citizen guards. Combat morale is calculated as weighted average based on soldier and guard numbers. Defender casualties in battle deduct from recruited army first, sparing citizen guards until army reserves are depleted. Overflow casualties apply to living guards in deterministic order. Recruited army casualties do not emit `citizen_died` events. In TC-ARMY.28, the test executes the real `CitizenController.die()` death path connected to `WorldView._on_citizen_died()` with an independent probe listener: asserts active guard job is released to `AVAILABLE` with `worker_id == ""`, controller `active_job` is nulled, guard is removed from `citizens_by_id` & `citizen_list`, recorded in `deceased_citizen_ids`, population accounting decrements, exactly one combat death event is triggered (`Chiến Binh Tử Trận`, `cause == "combat"`), exactly one `citizen_died` signal is emitted, duplicate `die()` calls are strictly idempotent with zero re-emitted signals, zero extra events, and zero population changes, and abstract army casualties emit zero citizen signals or events and cause zero population change.
    - **TC-ARMY.29 to TC-ARMY.30B (SaveManager End-to-End Roundtrip, Side Effect Verification & Campaign Safety):** Unit serialization roundtrip and legacy reset. Full `SaveManager.serialize_world_state` and `SaveManager.apply_loaded_state_to_world` integration verifies that non-default army fields survive Save -> Load -> Save roundtrips. Applying the same save state twice does not duplicate army units, WorldView citizens, HUD nodes, or signal handlers. Loading does not deduct recruitment resources or charge extra daily upkeep. Resource stocks after repeated loads remain strictly consistent with the saved state. Same-day daily upkeep remains strictly idempotent after restoring army state. Package 1K campaign state remains preserved across repeated loads. Applying a legacy save lacking `player_army` cleanly resets army state to 0 soldiers, supplied, day -1 without corrupting unrelated campaign state.
    - **TC-ARMY.31 (Upkeep Day Clock Validation, Malformed Clock Day Rejection & Evasion Prevention):** `SaveManager.validate_save_data()` enforces `last_upkeep_day <= clock_day` when `game_clock.current_day` is valid. When `game_clock.current_day` is present but malformed (string, float, zero, negative, array, non-dictionary), the save is rejected fail-closed. Validates that `apply_loaded_state_to_world()` rejects invalid save input before any destructive world reconstruction begins. In `PlayerArmyManager.deserialize()`, fail-closed normalization clamps future upkeep days to `TimeManager.current_day`.
    - **TC-ARMY.32 (Live Barracks Capacity & Dynamic HUD Refresh):** Under-construction barracks contribute 0 capacity, premature completion strictly refused; genuine completion raises capacity to 5 and updates HUD; damaged barracks reduces capacity to 0, disables recruit button, and preserves existing soldiers; reactivated barracks restores capacity to 5; demolished barracks drops capacity to 0 and preserves soldiers; HUD `recruit_cost_label` is dynamically formatted from `EconomyConfig.ARMY_RECRUIT_COST` and `EconomyConfig.RESOURCE_NAMES_VI`.
  - *Status:* **PASSED** (2026-10-19, Exit Code 0: 32/32 tests passed).

### Package 1M: Player Army Marching & Garrison Deployment
- **TC-MOVE.1 to TC-MOVE.32: Player Army Marching, Navigation, Garrison Deployment, Review Fix & Visual Verification Suite**
  - *Script:* `res://scripts/test/test_army_movement.gd`
  - *Acceptance Criteria:*
    - **TC-MOVE.1 to TC-MOVE.7 (State, Rally Point & Basic Navigation):** Initial state begins garrisoned at default Town Hall south plaza rally cell `(32, 33)`, empty path, and defense-ineligible (0 soldiers). Zero-soldier army move orders are rejected safely without state mutation. When recruited, ordering move calculates A* path via `GridNavigation`, transitions state to `MARCHING`, and navigates around solid obstacles and water. Invalid targets (out-of-bounds, solid building footprints, water, or same-cell orders) are rejected atomically fail-closed with zero state mutation. Discrete accumulator steps traverse 1 cell per 0.5s at 1x speed, emitting `army_moved`. Reaching destination transitions state to `IDLE_AT_FIELD` and excludes army from settlement defense. Calling `order_return_home()` routes back to rally point, transitions to `GARRISONED` upon arrival, and restores defense eligibility.
    - **TC-MOVE.8 to TC-MOVE.13 (Interruption, Dynamic Obstruction & Simulation Clock):** Calling `cancel_move()` halts army at current cell, clears path, and transitions to `IDLE_AT_FIELD`. Re-targeting mid-transit seamlessly recalculates a new route from the current cell. Movement strictly freezes when simulation is paused (`speed_mult == 0.0`). Accumulator scales proportionally across 1x, 2x, and 3x speeds. When an in-flight waypoint is dynamically blocked (e.g. building/palisade placed), `advance_movement` detects the obstacle and dynamically reroutes around it; if destination is completely trapped/unreachable, army safely halts at current position and transitions to `IDLE_AT_FIELD` without crashing or infinite looping.
    - **TC-MOVE.14 to TC-MOVE.18 (Defense Eligibility, Raid Casualties & Recruitment Gate):** Recruitment is strictly blocked with clear Vietnamese error diagnostics while army is marching or deployed in field. Defending force in `BattleCampaignManager.construct_defending_force()` excludes absent army units (`army_soldiers = 0`) so absent soldiers take zero casualties during settlement raids, allocating combat casualties to living civilian guards. Garrisoned army units join defense force and absorb casualties first. Depleting standing army to zero automatically resets army to clean `GARRISONED` state at home rally cell.
    - **TC-MOVE.19 to TC-MOVE.24 (Persistence, Validation Hardening & Walkability Recovery):** Full `SaveManager` serialization and deserialization roundtrip accurately preserves `current_cell`, `rally_cell`, `destination_cell`, `movement_state`, and `current_path`. In TC-MOVE.20, live `world_instance` army is genuinely in `MARCHING` state with a non-empty route when serialized; `apply_loaded_state_to_world()` restores the state cleanly; double-load into the world instance is strictly idempotent with zero `ArmyMarker` duplication; resource stocks, capacities, active population, upkeep day, and supply state are captured pre-load and verified identical across both loads without unintended deductions; post-reload advancement advances 1 step to the adjacent next waypoint, decreases path length by 1, and does not jump to destination; isolated `deserialize()` test proves deserialization causes 0 resource deductions. In TC-MOVE.21, legacy saves lacking movement fields cleanly default to `GARRISONED` at rally cell. In TC-MOVE.22, `SaveManager.validate_save_data()` fail-closed rejects 16 malformed payloads. In TC-MOVE.23, deserialization walkability verification detects blocked cells without teleporting. In TC-MOVE.24, `ArmyMarker` dynamically toggles visibility (hidden at 0, visible > 0).
    - **TC-MOVE.25 to TC-MOVE.28 (HUD Wiring & Map Targeting Mode):** HUD `ArmyPanel` displays live deployment status in Vietnamese via `DeploymentLabel`. Move and Return Home buttons properly enable/disable based on troop count and location. Starting targeting mode enables click-to-move on map and cancels with right-click or ESC key. Executing targeting dispatches move order, displays Vietnamese event banners, and exits targeting cleanly.
    - **TC-MOVE.29 (Finding B — Return Home Actions & Defense Restoration):** When army is ordered to march but has not yet advanced from `rally_cell`, calling `order_return_home()` cleanly cancels the outbound order (`action: "canceled_at_rally"`), clears `current_path`, resets `destination_cell = rally_cell`, sets `movement_state = GARRISONED`, and immediately restores defense eligibility (`is_defense_eligible() == true`). When already garrisoned, returns `action: "already_garrisoned"`. When away from base, returns `action: "marching_home"`.
    - **TC-MOVE.30 (Finding C — Mutual Exclusion of Construction & Army Targeting):** Starting army targeting cancels active building placement in `WorldView` and hides ghost preview; selecting a building in HUD or requesting building placement cancels active army targeting; cancelling placement clears ghost node; click routing routes exclusively to the intended action without accidental construction.
    - **TC-MOVE.31 (Finding 5 — Minor HUD Contract Verification):** `PlayerArmyManager.order_move()` returns both `"steps"` and `"path_length"` matching the exact route size; HUD displays the positive step count in Vietnamese event banner.
    - **TC-MOVE.32 (HUD Return Home Feedback Banners):** HUD accurately reports all return-home outcomes in Vietnamese event banners: canceling outbound march at rally cell displays `"Đóng Quân Tại Căn Cứ"` ("Đã hủy lệnh hành quân, quân đội tiếp tục đóng quân tại căn cứ."); already garrisoned at rally displays `"Tại Căn Cứ"` ("Quân đội hiện đang đóng quân tại căn cứ."); marching home from the field displays `"Rút Về Căn Cứ"` ("Quân đội đang hành quân trở về căn cứ doanh trại.").
  - *Status:* **PASSED** (2026-10-20, Exit Code 0: 32/32 tests passed).

### Package 1N: Player-Led Abstract Offensive Campaigns
- **TC-OFFENSE.1 to TC-OFFENSE.14: Player-Led Offensive Campaign Verification Suite**
  - *Script:* `res://scripts/test/test_offensive_campaign.gd`
  - *Acceptance Criteria:*
    - **TC-OFFENSE.1 (Valid Attack Execution):** Army deployed outside settlement (`IDLE_AT_FIELD` away from `rally_cell`) targeting a hostile faction with military power > 0 succeeds; resolves battle via `BattleResolver.resolve_battle()`; increments campaign sequence; emits `offensive_campaign_resolved` and `battle_resolved` signals with complete context dictionary.
    - **TC-OFFENSE.2 (Zero-Soldier Rejection):** Launching an attack with 0 soldiers fails closed with informative Vietnamese feedback ("Quân đội không có binh sĩ để tiến hành tấn công.") and zero state mutations.
    - **TC-OFFENSE.3 (Garrisoned Rejection):** Launching an attack while garrisoned at base or at `rally_cell` fails closed with Vietnamese feedback and zero state mutations.
    - **TC-OFFENSE.4 (Marching Rejection):** Launching an attack while actively marching (`movement_state == MARCHING`) fails closed with Vietnamese feedback and zero state mutations.
    - **TC-OFFENSE.5 (Target Ineligibility Rejections):** Attacks against peaceful factions (not at war), non-existent factions, or factions with 0 military power fail closed with distinct Vietnamese error messages and zero mutations.
    - **TC-OFFENSE.6 (Deterministic Battle Resolution):** Campaigns executed with identical seeds produce 100% identical combat scores, casualty counts, explanations, and victor outcomes.
    - **TC-OFFENSE.7 (Casualty Bounds):** Attacker casualties are bounded within $[0, \text{initial\_player\_soldiers}]$; defender casualties are bounded within $[0, \text{initial\_enemy\_troops}]$.
    - **TC-OFFENSE.8 (State Mutations Application):** Player casualties deduct accurately from standing army via `PlayerArmyManager.remove_casualties()`; enemy military power reduces accurately by $30.0 \times \text{casualties}$, clamped to floor $0.0$.
    - **TC-OFFENSE.9 (Post-Battle Normalization):** Total casualty wipeout normalizes army to clean `GARRISONED` status at `rally_cell`; surviving soldiers remain deployed at field cell (`IDLE_AT_FIELD`) without teleportation.
    - **TC-OFFENSE.10 (State Immutability on Rejections):** Rejected attacks do not mutate army counts, movement states, coordinates, faction data, resources, or diplomacy.
    - **TC-OFFENSE.11 (HUD Event Banner Integration):** HUD event banners accurately display campaign outcome, faction name, casualties, remaining troops, and remaining enemy power in Vietnamese.
    - **TC-OFFENSE.12 (Save/Load Persistence, Schema Validation & Integrated World Lifecycle):** Schema validation confirms `offensive_sequence >= 0`, `pending_raids` as Dictionary, and `processed_raids` as Dictionary under `battle_campaign`. Component-level serialization roundtrip preserves sequence number. Real live `world_instance` integration test covers Parts A-D: Part A sets up live army deployed `IDLE_AT_FIELD` away from rally, configures hostile `rival_military` with power > 0, schedules pending settlement raid, connects `offensive_campaign_resolved` signal tracker, launches valid offensive campaign, asserts launch success, exactly 1 signal emission, and captures post-battle army, faction, sequence, raid, and resource states; Part B serializes via `SaveManager.serialize_world_state()` and verifies schema validity, army coordinates/count, faction power, sequence, and raid preservation; Part C perturbs in-memory live values (army count/state, faction power/war status, sequence, raids, resource stock), clears emission tracker, executes `SaveManager.apply_loaded_state_to_world()`, and verifies exact restoration of all post-battle state, intact pending raids, and strictly 0 additional signal emissions; Part D applies loaded state a second time, verifying double-load idempotency, 0 additional signal emissions, unchanged army/faction/resource values without double deductions, and at most 1 `ArmyMarker` node in `citizens_container`.
    - **TC-OFFENSE.13 (Raid Loop Independence):** Offensive campaigns do not alter, cancel, or re-schedule incoming settlement defense raids; signing peace still cancels scheduled raids normally.
    - **TC-OFFENSE.14 (Movement Rules Contract):** Deployed armies retain full Package 1M movement capabilities: ordering return home initiates march, step advancement reaches rally cell, transitions to `GARRISONED`, and restores defense eligibility.
  - *Status:* **PASSED** (2026-10-20, Exit Code 0: 14/14 tests passed).

### Package 1O: Post-Battle Diplomatic Consequences
- **TC-DIPLO.1 to TC-DIPLO.11: Post-Battle Diplomatic Consequences Suite**
  - *Script:* `res://scripts/test/test_battle_diplomacy_consequences.gd`
  - *Acceptance Criteria:*
    - **TC-DIPLO.1 (Offensive Campaign Opinion Penalty):** A successful player-led offensive campaign applies exactly the canonically configured penalty (-8.0, `FactionManager.OPINION_PENALTY_OFFENSIVE_CAMPAIGN`) to the target faction's opinion. The returned campaign context dictionary contains `diplomatic_opinion_penalty`, `new_opinion`, and `disposition`.
    - **TC-DIPLO.2 (Settlement Raid Opinion Penalty):** A successfully resolved settlement raid applies exactly the canonically configured penalty (-10.0, `FactionManager.OPINION_PENALTY_SETTLEMENT_RAID`) to the attacking faction's opinion. The returned raid context contains `diplomatic_opinion_penalty`, `new_opinion`, and `disposition`.
    - **TC-DIPLO.3 (Complete Boundary Clamping -100.0 and +100.0):** Opinion penalties and adjustments strictly clamp at both lower (-100.0) and upper (100.0) boundaries. Verifies offensive campaign (-8.0) and raid (-10.0) penalties clamping from -95.0/-96.0 to -100.0, and further attacks staying at -100.0. Furthermore, directly exercises `FactionManager.modify_opinion()` on non-war factions: boosts from 95.0 clamp to exactly 100.0 with 1 signal emitting `Disposition.ALLIED`, further boosts while at 100.0 remain at 100.0; reductions from -95.0 clamp to exactly -100.0 with 1 signal emitting `Disposition.HOSTILE`, further reductions while at -100.0 remain at -100.0.
    - **TC-DIPLO.4 (Signal Emission Exactly Once):** Exactly one `FactionManager.relation_changed` signal is emitted per successful battle consequence (offensive campaign or settlement raid), with matching payload (`id`, `opinion`, `disposition`).
    - **TC-DIPLO.5 (Fail-Closed Rejection Immutability):** Ineligible offensive campaigns (0 soldiers, garrisoned at base/rally, actively marching, non-war faction, 0 enemy military power) fail closed, causing zero opinion or disposition mutation and emitting zero signals.
    - **TC-DIPLO.6 (Raid Eligibility Immutability):** Raids that are not yet due, already processed for the day, or non-existent fail closed, applying zero diplomatic mutation and emitting zero signals.
    - **TC-DIPLO.7 (Hostile Disposition During War):** While at war (`is_at_war == true`), faction disposition remains strictly locked to `Disposition.HOSTILE` regardless of intermediate opinion values.
    - **TC-DIPLO.8 (Post-Peace Disposition Recalculation):** Signing peace clears war status, applies the peace opinion boost (+20.0), and updates disposition according to post-battle opinion via `FactionData.sign_peace()` and `FactionData.recalculate_disposition()`: hostile for opinion <= -40.0, neutral for -40.0 < opinion < 25.0, friendly for opinion >= 25.0.
    - **TC-DIPLO.9 (SaveManager Persistence & Double-Load Idempotency):** Live `WorldView` battle results serialize cleanly through `SaveManager.serialize_world_state()` with intact faction opinions and dispositions. Calling `SaveManager.apply_loaded_state_to_world()` accurately restores post-battle opinions and dispositions with zero signal emissions. A second consecutive load executes idempotently with zero opinion mutations, zero signal emissions, and zero duplicated markers.
    - **TC-DIPLO.10 (Combat Mechanics Integrity):** Casualties, military power deductions, plunder, raid schedules, and campaign sequences operate identically alongside diplomatic consequence application.
    - **TC-DIPLO.11 (Diplomacy Regression Suite):** Existing non-aggression pacts, gifts, war declarations, and peace treaties continue to function with full behavioral fidelity and correct signal emission.
  - *Status:* **PASSED** (2026-10-20, Exit Code 0: 11/11 tests passed).

### Package 1P: Emerging Faction Ascension Gates
- **TC-EMERGE.1 to TC-EMERGE.11: Emerging Faction Ascension Gates Verification Suite**
  - *Script:* `res://scripts/test/test_emerging_faction_ascension.gd`
  - *Acceptance Criteria:*
    - **TC-EMERGE.1 (Happy Path Ascension):** When all gates are satisfied (neutral tribe exists, population $\ge 45$, day $\ge 10$, wood $\ge 60$, herbs $\ge 30$, stability $\ge 50.0$), `FactionManager.update_daily_simulation(10)` evolves the neutral tribe into an emerging power (`type = "emerging_power"`, `name = "Liên Minh Rừng Thiêng"`, `military_power = 55.0`, `stability = 85.0`). Emits `emerging_faction_ascended` signal exactly once with matching ID and name. Verifies that wood and herbs stocks are NOT deducted upon ascension.
    - **TC-EMERGE.2 (Population Gate):** When population $< 45$ (e.g. 40, becoming 41 on daily tick), `can_emerging_faction_ascend(10)` returns false, no signal is emitted, and faction type and name remain unchanged (`neutral_tribe`, `Bản Làng Rừng Xanh`).
    - **TC-EMERGE.3 (Time Gate):** When simulation day $< 10$ (e.g. Day 9 with population $\ge 45$), `can_emerging_faction_ascend(9)` returns false, no ascension occurs, and no signal is emitted. At Day 10, `can_emerging_faction_ascend(10)` returns true.
    - **TC-EMERGE.4 (Resource Gate Fail-Closed):** Deficits in either essential resource (wood $< 60$ or herbs $< 30$) or missing resource dictionary keys cause `can_emerging_faction_ascend(10)` to return false and prevent ascension without side effects.
    - **TC-EMERGE.5 (Stability Gate & Boundary Analysis):** Stability $< 50.0$ (e.g. 49.9) fails closed and blocks ascension. Stability $\ge 50.0$ (tested at the exact boundary $50.0$) satisfies the gate and triggers ascension cleanly.
    - **TC-EMERGE.6 (Recovery and Retry on Next Valid Day):** A tribe blocked on Day 10 due to insufficient herbs (herbs $= 20$) recovers after resource replenishment (herbs $= 35$), triggering ascension on Day 11 simulation tick.
    - **TC-EMERGE.7 (Exactly-Once Event Emission & Idempotency):** Signal `emerging_faction_ascended` is emitted exactly once on the ascension tick. Subsequent daily simulation ticks on Day 11, 12, 13 do NOT re-emit the signal and maintain stable evolved attributes.
    - **TC-EMERGE.8 (Single Emerging Power Rule):** When the world already contains an emerging power (`type == "emerging_power"`), `has_emerging_power()` returns true, blocking subsequent ascensions even if other criteria are met.
    - **TC-EMERGE.9 (Missing Faction Safety & Null Resilience):** If `neutral_tribe` is removed or null, `can_emerging_faction_ascend(10)` returns false, `update_daily_simulation(10)` returns through normal execution flow without mutating unrelated factions (`rival_military`, `rival_merchant`), `neutral_tribe` remains absent, zero emerging powers exist in the world, and zero `emerging_faction_ascended` signals are emitted.
    - **TC-EMERGE.10 (Integrated SaveManager Persistence & Reload Idempotency):** Serializing a world state where neutral tribe has ascended preserves `name = "Liên Minh Rừng Thiêng"`, `type = "emerging_power"`, `military_power = 55.0`, `stability = 85.0`, and full `resources` dictionary. Passes `SaveManager.validate_save_data()` schema validation. Attaching an emission spy before the first load verifies that strictly zero `emerging_faction_ascended` signals are emitted during the first `apply_loaded_state_to_world()` call, subsequent daily simulation tick, or second load application. Restored attributes and resources match post-ascension state and execute idempotently across loads.
    - **TC-EMERGE.11 (HUD Event Banner Integration & Diplomacy UI Refresh):** HUD `set_faction_manager()` connects to `emerging_faction_ascended`. Initial diplomacy UI renders `Bản Làng Rừng Xanh`. Upon ascension, displays Vietnamese event banner (`"Thế Lực Mới Nổi! Liên Minh Rừng Thiêng đã chính thức trỗi dậy thành một cường bang mới!"`) and dynamically triggers `_refresh_diplomacy_ui()`, actively verifying that rendered faction cards in `factions_list_vbox` update to `"Liên Minh Rừng Thiêng"` and no longer display `"Bản Làng Rừng Xanh"`.
  - *Status:* **PASSED** (2026-10-20, Exit Code 0: 11/11 tests passed).

### Package 1Q: Faction Strategic Profiles & Existence Status
- **TC-FPROF.1 to TC-FPROF.9: Faction Strategic Profiles & Existence Status Suite**
  - *Script:* `res://scripts/test/test_faction_profiles.gd`
  - *Acceptance Criteria:*
    - **TC-FPROF.1 (Initialization):** Initial factions instantiate with correct default profile mappings: `rival_military` has `strategic_goal = "military_expansion"` and `existence_status = "active"`; `rival_merchant` has `strategic_goal = "trade_dominance"` and `existence_status = "active"`; `neutral_tribe` has `strategic_goal = "community_growth"` and `existence_status = "active"`.
    - **TC-FPROF.2 (Stable IDs & Localized Labels):** Internal IDs are immutable string identifiers (`military_expansion`, `trade_dominance`, `community_growth`, `consolidate_power`, `active`, `in_exile`, `eliminated`). Centralized static helpers (`FactionData.get_strategic_goal_label()` and `FactionData.get_existence_status_label()`) accurately map to Vietnamese display names (`"Mở rộng quân sự"`, `"Phát triển thương mại"`, `"Phát triển cộng đồng"`, `"Củng cố thế lực"`, `"Hoạt động"`, `"Lưu vong"`, `"Bị loại bỏ"`), returning `"Không xác định"` on unrecognized values.
    - **TC-FPROF.3 (Ascension Integration):** When `neutral_tribe` satisfies ascension gates and evolves into `emerging_power`, its `strategic_goal` mutates to `consolidate_power` while `existence_status` remains `active`. Signal `emerging_faction_ascended` is emitted exactly once. Subsequent simulation ticks preserve `consolidate_power` and do not re-emit the signal.
    - **TC-FPROF.4 (Save Serialization):** `SaveManager.serialize_world_state()` records both `strategic_goal` and `existence_status` for all factions under `data["factions"]["factions"]`, matching live object values.
    - **TC-FPROF.5 (Save/Load Roundtrip):** World state with modified strategic goals and existence statuses (e.g. ascended tribe with `consolidate_power` and rival military marked `in_exile`) preserves exact values through serialization and `SaveManager.apply_loaded_state_to_world()`.
    - **TC-FPROF.6 (Legacy Save Compatibility):** Legacy saves omitting `strategic_goal` and `existence_status` pass schema validation and restore with documented fallbacks: `emerging_power` defaults to `consolidate_power`, `rival_military` to `military_expansion`, `rival_merchant` to `trade_dominance`, unascended `neutral_tribe` to `community_growth`, and all default to `active` existence status.
    - **TC-FPROF.7 (Invalid Data Safety - Fail-Closed):** Invalid strategic goals or existence statuses in save data are rejected by `SaveManager.validate_save_data()` and abort `apply_loaded_state_to_world()` without mutating live factions. Code setters `set_strategic_goal()` and `set_existence_status()` return false and reject invalid values without mutating existing state.
    - **TC-FPROF.8 (HUD Rendering & Dynamic Refresh):** Faction cards in `HUD.factions_list_vbox` display Vietnamese labels for goal and status (`"Mục tiêu: %s | Trạng thái: %s"`). Raw internal identifiers are never displayed. When `neutral_tribe` ascends, the diplomacy UI refreshes to show `"Củng cố thế lực"` on the card.
    - **TC-FPROF.9 (Load Idempotency):** Consecutive calls to `SaveManager.apply_loaded_state_to_world()` do not create duplicate factions, emit zero ascension signals, preserve exact faction counts, and maintain identical opinions, goals, and statuses across loads.
  - *Status:* **PASSED** (2026-10-20, Exit Code 0: 9/9 tests passed).

### Package 1R: Deterministic Faction Strategic Decision Engine
- **TC-FSTRAT.1 to TC-FSTRAT.7: Faction Strategy Planner Verification Suite**
  - *Script:* `res://scripts/test/test_faction_strategy_planner.gd`
  - *Acceptance Criteria:*
    - **TC-FSTRAT.1 (Canonical Goal Mapping):** Evaluator correctly translates canonical strategic goals to corresponding strategic intents (`military_expansion` $\to$ `military_buildup`, `trade_dominance` $\to$ `trade_expansion`, `community_growth` $\to$ `community_development`, `consolidate_power` $\to$ `power_consolidation`). Evaluator returns structured result dictionary containing `faction_id`, `strategic_goal`, `intent_id`, `eligible: true`, `reason_code: "GOAL_ALIGNED"`, and `posture: "peacetime"`. Static helper `get_intent_label()` maps intents to Vietnamese localized names (`"Tăng cường quân sự"`, `"Mở rộng giao thương"`, `"Phát triển cộng đồng"`, `"Củng cố quyền lực"`, `"Không xác định"`).
    - **TC-FSTRAT.2 (Deterministic Repeatability):** Evaluating the same faction 50 consecutive times yields 100% identical dictionary outputs with zero variation, zero random branching, and zero internal attribute mutation (`opinion`, `military_power`, `population`, `strategic_goal`, `existence_status`).
    - **TC-FSTRAT.3 (Invalid Profile Safety & Fail-Closed):** Factions with null reference, empty goal (`""`), unrecognized goal (e.g. `"galactic_conquest"`), or invalid existence status fail closed gracefully: `eligible: false`, `intent_id: "none"`, with specific diagnostic reason codes (`ERR_NULL_FACTION`, `ERR_INVALID_GOAL`, `ERR_INVALID_STATUS`). Faction properties, including empty goals, unrecognized goals, and statuses, remain completely unmutated without engine exceptions.
    - **TC-FSTRAT.4 (Existence Status Gating):** Only factions with `existence_status == "active"` receive eligible active-world intents (`eligible: true`). Factions marked `in_exile` return `eligible: false`, `intent_id: "none"`, and `reason_code: "INELIGIBLE_IN_EXILE"`. Factions marked `eliminated` return `eligible: false`, `intent_id: "none"`, and `reason_code: "INELIGIBLE_ELIMINATED"`. Factions with `military_power == 0.0` but `existence_status == "active"` remain `active` and eligible (military defeat does not implicitly alter existence status).
    - **TC-FSTRAT.5 (Daily Simulation Integration & Wartime Posture):** `FactionManager.update_daily_simulation(day)` evaluates strategic intent for all active factions deterministically in sorted alphabetical key order (`sorted_ids.sort()`), emitting `strategic_intent_evaluated(faction_id, intent_data)` once per eligible active faction per invocation of `FactionManager.update_daily_simulation()`. Factions with wartime posture (`is_at_war == true`) receive `posture: "wartime"` and `reason_code: "WARTIME_POSTURE"` both in direct evaluation and daily simulation signal payloads while remaining eligible with intent aligned to strategic goal, leaving faction fields (including `disposition`) unmutated. Direct query APIs `get_faction_strategic_intent(faction_id)` and `evaluate_all_strategic_intents()` provide consistent results without side effects.
    - **TC-FSTRAT.6 (Emerging Faction Ascension Compatibility & Existence Status Gating):** When an active `neutral_tribe` evolves into an `emerging_power` during daily simulation, its strategic intent immediately transitions from `community_development` to `power_consolidation` in that same simulation day without stale reads, duplicate emissions, or delayed evaluation. Inactive tribes (`in_exile` and `eliminated`) are strictly gated: `can_emerging_faction_ascend(10)` returns false; daily simulation tick suppresses `emerging_faction_ascended` emission; population does not increment; all faction attributes (name, type, military power, stability, strategic goal, resources, existence status) remain untouched; and `strategic_intent_evaluated` emission is suppressed.
    - **TC-FSTRAT.7 (Direct Evaluator Immutability & Simulation Integration Verification):** Direct evaluation via `FactionStrategyPlanner.evaluate_faction_intent()`, `FactionManager.get_faction_strategic_intent()`, and `FactionManager.evaluate_all_strategic_intents()` is strictly read-only and immutable across single and repeated evaluations, leaving all faction fields (`id`, `name`, `type`, `disposition`, `opinion`, `military_power`, `stability`, `population`, `is_at_war`, `has_nap`, `has_alliance`, `strategic_goal`, `existence_status`, and deep-copied `resources`) invariant. Across daily simulation ticks on a pre-ascension world, faction identities, types, dispositions, opinions, strategic goals, and existence statuses remain unmutated, and `neutral_tribe` increases population by `+1/day` while preserving its Wood and Herbs ascension reserves.
  - *Status:* **PASSED** (2026-10-23, Exit Code 0: 7/7 tests passed).

### Package 1S: Faction Strategic Intent Execution
- **TC-FEXEC.1 to TC-FEXEC.14: Faction Strategy Executor Verification Suite**
  - *Script:* `res://scripts/test/test_faction_strategy_execution.gd`
  - *Acceptance Criteria:*
    - **TC-FEXEC.1 (Valid `military_buildup` Execution):** Consumes `10 Metal + 25 Gold`, increases `military_power` by `+5.0`, clamps at ceiling `120.0`, works in both peacetime and wartime posture, and preserves `strategic_goal` and `existence_status`.
    - **TC-FEXEC.2 (Valid `trade_expansion` Execution & Wartime Block):** Consumes `5 Tools`, adds `+30 Gold` (up to `1000`), increases `stability` by `+2.0` (up to `95.0`). Blocked during wartime (`REASON_BLOCKED_BY_WAR`) with zero resource consumption, and resumes cleanly on peace.
    - **TC-FEXEC.3 (Valid `community_development` Execution):** Consumes `10 Wood + 5 Herbs` and increases `population` by `+1` (up to `80`) and `stability` by `+2.0` (up to `90.0`); pre-ascension `neutral_tribe` daily simulation integrates `+1` daily settlement growth without depleting Wood/Herbs ascension reserves.
    - **TC-FEXEC.4 (Valid `power_consolidation` Execution & Post-Ascension Gating):** Requires `type == "emerging_power"` and `strategic_goal == "consolidate_power"`; consumes `15 Wood + 10 Herbs` and increases `military_power` by `+4.0` (up to `90.0`) and `stability` by `+2.0` (up to `95.0`); rejects non-ascended factions fail-closed (`REASON_INELIGIBLE_CONSOLIDATION_STATE`).
    - **TC-FEXEC.5 (Insufficient Resources Fail-Closed):** Missing or insufficient resources for any intent return `REASON_INSUFFICIENT_RESOURCES` with zero partial resource deductions and zero attribute mutations.
    - **TC-FEXEC.6 (Cap Reached Fail-Closed):** When all target attributes for an intent are already at ceiling, returns `REASON_AT_CAP` without deducting resources.
    - **TC-FEXEC.7 (Inactive Factions Gating):** Factions in `in_exile` or `eliminated` statuses are rejected with `REASON_INELIGIBLE_STATUS` on direct calls and skipped during `update_daily_simulation(day)`.
    - **TC-FEXEC.8 (Invalid Input, Corrupted Faction Resources & Trade Gold Overflow/Cap Regression Protection):** Null faction, `day < 1`, malformed decision dictionary, mismatched decision intent, unrecognized goal, invalid status, or corrupted faction `resources` (negative `Gold`, string `Gold`, fractional float `Gold`, non-finite `INF`, boolean `Metal`) fail closed (`REASON_ERR_INVALID_RESOURCES` for resource violations) with zero resource deductions, zero attribute mutations, and untouched `last_executed_day`. Restoring valid resources allows normal execution immediately. Additionally verifies `BUG-1S-03` pre-addition Gold headroom calculation in `trade_expansion`: normal headroom (`985 -> 1000`, delta `+15`), exact Gold cap (`1000 -> 1000`, delta `0`), above Gold cap (`1200 -> 1200`, delta `0` without reducing existing Gold while deducting `5 Tools` and increasing `stability` by `+2.0`), and maximum signed 64-bit integer Gold (`9223372036854775807` preserved without integer overflow or negative wrap).
    - **TC-FEXEC.9 (Same-Day Idempotency & Deterministic Order):** `update_daily_simulation(day)` executes active factions in sorted alphabetical order (`neutral_tribe`, `rival_merchant`, `rival_military`); calling `update_daily_simulation(day)` a second time on the same day returns `REASON_ALREADY_EXECUTED_TODAY` with zero repeat mutations.
    - **TC-FEXEC.10 (Ascension & `power_consolidation` Ordering):** On the exact day `neutral_tribe` ascends (`Day 10`), ascension sets `military_power = 55.0` and `stability = 85.0`, and `power_consolidation` records `REASON_ASCENDED_THIS_TICK` without double-boosting or deducting resources; on `Day 11`, `power_consolidation` executes normally (`55.0 -> 59.0`, `85.0 -> 87.0`).
    - **TC-FEXEC.11 (Planner Purity):** Repeated calls to `FactionStrategyPlanner.evaluate_faction_intent()`, `fm.get_faction_strategic_intent()`, and `fm.evaluate_all_strategic_intents()` leave all faction fields and executor `last_executed_day` untouched.
    - **TC-FEXEC.12 (Deterministic Multi-Day Equivalence):** Two independent `FactionManager` instances simulated across Days `1..14` produce 100% identical faction states, resources, and `last_executed_days`.
    - **TC-FEXEC.13 (Save/Load Roundtrip, Legacy Fallback, Double-Load & Clock/Resource Fail-Closed Validation):** `SaveManager` serializes and restores `factions.strategy_executor`; re-running the loaded day (`Day 12`) does not re-execute actions; double-load is idempotent; legacy saves lacking `strategy_executor` load cleanly; future `last_executed_days` (`13 > current_day == 12`) and future `last_tribe_growth_day` (`13 > current_day == 12`) are rejected fail-closed before world mutation (alongside a separate test for `> 36500`); second-layer `deserialize_executor_state(data, current_day)` filters future days; and corrupted faction `resources` in save data (non-Dictionary, negative values, strings, booleans, fractional floats, `INF`, unknown keys) are rejected fail-closed with zero world state mutation.
    - **TC-FEXEC.14 (Cross-System Regression):** Military power gained via `military_buildup` translates into attacking troop counts in `BattleCampaignManager.construct_attacking_force()`, and war/peace/gift diplomacy flows operate cleanly.
  - *Status:* **PASSED** (2026-10-24, Exit Code 0: 14/14 tests passed, 951 checks passed).

### Package 1T: Deterministic Autonomous Faction Diplomacy
- **TC-FDIP.1 to TC-FDIP.16: Autonomous Faction Diplomacy Verification Suite**
  - *Script:* `res://scripts/test/test_faction_diplomacy_ai.gd`
  - *Acceptance Criteria:*
    - **TC-FDIP.1 (Planner War Eligibility):** `FactionDiplomacyPlanner.evaluate_diplomatic_action(fac)` returns `action_id = "declare_war"`, `eligible = true`, and `reason_code = "WAR_PREREQUISITES_MET"` for active `rival_military` (`military_expansion`) and ascended `emerging_power` (`consolidate_power`) when `opinion <= -60.0`, `military_power >= 65.0`, `stability >= 50.0`, and no war or treaty is active.
    - **TC-FDIP.2 (War Exact Boundary Thresholds):** Exact boundaries (`opinion == -60.0`, `military_power == 65.0`, `stability == 50.0`) are eligible for `declare_war`, whereas `-59.99` opinion (`OPINION_ABOVE_WAR_THRESHOLD`), `64.99` military power (`MILITARY_BELOW_WAR_THRESHOLD`), and `49.99` stability (`STABILITY_BELOW_WAR_THRESHOLD`) are rejected.
    - **TC-FDIP.3 (War Blocked by Treaties or Existing War):** Active `has_nap` or `has_alliance` blocks war (`BLOCKED_BY_TREATY`), and factions already at war with sufficient military/stability return `WARTIME_CONTINUES`.
    - **TC-FDIP.4 (War Blocked by Non-Aggressive Goal or Pre-Ascension State):** `rival_merchant` (`trade_dominance`), pre-ascension `neutral_tribe` (`community_growth`), and unascended `neutral_tribe` with `consolidate_power` never initiate war even at `-100.0` opinion and `100.0` military/stability.
    - **TC-FDIP.5 (Planner Peace Eligibility):** Factions at war with `existence_status` in `["active", "in_exile"]` return `action_id = "sign_peace"`, `eligible = true` when `military_power <= 20.0` (`PEACE_MILITARY_DEPLETED`), `stability <= 25.0` (`PEACE_STABILITY_LOW`), or both (`PEACE_MILITARY_AND_STABILITY_LOW`).
    - **TC-FDIP.6 (Peace Exact Boundary Thresholds):** Exact boundaries (`military_power == 20.0` or `stability == 25.0`) trigger `sign_peace`, whereas `military_power == 20.01` and `stability == 25.01` continue war (`WARTIME_CONTINUES`), and peaceful factions never trigger `sign_peace`.
    - **TC-FDIP.7 (Inactive & Invalid States Fail-Closed):** Null faction (`ERR_NULL_FACTION`), `in_exile` peacetime faction (`INELIGIBLE_EXILE_PEACETIME`), `eliminated` faction in peacetime or wartime (`INELIGIBLE_ELIMINATED`), invalid status (`ERR_INVALID_STATUS`), invalid goal (`ERR_INVALID_GOAL`), and `NaN` numeric fields (`ERR_INVALID_STATE`) fail closed without mutation or recording `last_diplomacy_day`.
    - **TC-FDIP.8 (Planner 100% Pure & Side-Effect-Free):** 25 repeated calls to `FactionDiplomacyPlanner.evaluate_diplomatic_action()`, `get_faction_diplomatic_decision()`, and `evaluate_all_diplomatic_decisions()` leave all faction fields, resources, and `last_diplomacy_day` untouched.
    - **TC-FDIP.9 (Autonomous War Execution & Raid Scheduling):** `execute_faction_diplomatic_action("rival_military", 4)` routes through `declare_war()`, setting `is_at_war = true`, `disposition = HOSTILE`, `opinion = -100.0`, emitting `war_declared`, `relation_changed`, `diplomatic_action_evaluated`, and `diplomatic_action_executed`, and scheduling a raid in `BattleCampaignManager`.
    - **TC-FDIP.10 (Autonomous Peace Execution & Pending Raid Cancellation):** `execute_faction_diplomatic_action()` and `update_daily_simulation()` route `sign_peace` for both `active` and `in_exile` factions through `propose_treaty(..., "peace")`, clearing `is_at_war`, adding `+20.0` opinion, emitting `peace_signed`, and cancelling pending raids in `BattleCampaignManager`.
    - **TC-FDIP.11 (Daily Simulation Ordering & Tampered Override Rejection):** In `update_daily_simulation(day)`, autonomous diplomacy executes before strategic intent evaluation/execution so a faction declaring war on Day $D$ immediately evaluates its strategic intent in `"wartime"` posture on Day $D$, and a merchant faction signing peace on Day $D$ immediately resumes `trade_expansion` on Day $D$. Invalid day (`<= 0`) or tampered `decision_override` fails closed (`ERR_INVALID_DAY`, `ERR_INVALID_DECISION`).
    - **TC-FDIP.12 (Same-Day Idempotency & Anti-Oscillation):** Once evaluated on Day 5, a faction cannot re-evaluate or oscillate from war back to peace on Day 5 (`ALREADY_EVALUATED_TODAY`) even if its military power drops mid-day; peace executes cleanly on Day 6.
    - **TC-FDIP.13 (HUD Vietnamese Event Banners):** Autonomous war and peace signals update the HUD `event_banner` with Vietnamese titles (`"Chiến Tranh!"`, `"Hòa Bình Lập Lại!"`) including the faction's localized name (`"Cổ Thành Thiết Giáp"`) and refresh the diplomacy UI.
    - **TC-FDIP.14 (Deterministic Multi-Day Equivalence):** Two independent `FactionManager` instances simulated across Days `1..14` with autonomous war and peace transitions produce 100% identical faction states, resources, `last_diplomacy_days`, and `last_executed_days`.
    - **TC-FDIP.15 (Save/Load Persistence & Fail-Closed Validation):** `SaveManager` serializes and restores `factions.strategy_executor.last_diplomacy_days`; re-running Day 8 after load does not re-evaluate or oscillate diplomacy; double-load is idempotent; legacy saves omitting `last_diplomacy_days` load cleanly; and non-dictionary, zero/negative, or future `last_diplomacy_days` (`9 > game_clock.current_day == 8`) are rejected fail-closed before world mutation.
    - **TC-FDIP.16 (Player-Directed Diplomacy Regression):** Player gifts, NAP, Alliance, manual war declaration, and manual peace treaties continue to work cleanly alongside autonomous diplomacy.
  - *Status:* **PASSED** (2026-10-24, Exit Code 0: 16/16 tests passed, 437 checks passed).

### Package 1U: Pairwise Faction Relations Foundation
- **TC-FREL.1 to TC-FREL.16: Pairwise Faction Relations Verification Suite**
  - *Script:* `res://scripts/test/test_faction_relation_matrix.gd`
  - *Acceptance Criteria:*
    - **TC-FREL.1 (Default Initialization):** `FactionManager` initializes 3 canonical pairwise records (`neutral_tribe__rival_merchant`, `neutral_tribe__rival_military`, `rival_merchant__rival_military`) in sorted order with `opinion_a_to_b = 0.0`, `opinion_b_to_a = 0.0`, `is_at_war = false`, `has_nap = false`, and `has_alliance = false`.
    - **TC-FREL.2 (Canonical Pair Identity & Symmetry):** Both `(A, B)` and `(B, A)` resolve to the exact same `pair_key` and `FactionRelationData` instance with `faction_a < faction_b`.
    - **TC-FREL.3 (Directional Opinions, Clamping & Disposition):** Setting or modifying `A -> B` opinion updates only that direction (`B -> A` remains independent), clamps to `[-100.0, 100.0]`, computes directional disposition (`HOSTILE`, `NEUTRAL`, `FRIENDLY`, `ALLIED`), and emits `faction_pair_opinion_changed`.
    - **TC-FREL.4 (Invalid Pair & Non-Finite Rejection):** Self-relations (`A == B`), unknown faction IDs, empty IDs, and non-finite/non-numeric opinion inputs (`NaN`, `INF`, strings) fail closed with explicit `PAIR_REASON_ERR_*` codes and zero state mutation.
    - **TC-FREL.5 (Pairwise War Declaration):** `declare_war_between_factions()` sets `is_at_war = true`, clears `has_nap = false` and `has_alliance = false`, applies `-50.0` opinion delta in both directions, emits `faction_pair_war_declared`, and rejects duplicate war declarations (`ERR_ALREADY_AT_WAR`).
    - **TC-FREL.6 (Pairwise Peace):** `sign_peace_between_factions()` / `propose_treaty_between_factions(..., "peace")` requires `is_at_war == true` (`ERR_NOT_AT_WAR` when peaceful), clears war, applies `+20.0` opinion delta in both directions, emits `faction_pair_peace_signed`, and supports both `active` and `in_exile` factions.
    - **TC-FREL.7 (Pairwise NAP):** `sign_nap_between_factions()` requires peace (`ERR_AT_WAR`), no existing NAP (`ERR_ALREADY_HAS_NAP`), and mutual opinion `>= 0.0` (`ERR_INSUFFICIENT_OPINION`), sets `has_nap = true`, and applies `+15.0` opinion delta in both directions.
    - **TC-FREL.8 (Pairwise Alliance):** `sign_alliance_between_factions()` requires peace, no existing Alliance (`ERR_ALREADY_ALLIED`), and mutual opinion `>= 60.0`, sets `has_alliance = true` and `has_nap = true`, applies `+25.0` opinion delta in both directions, and rejects unknown treaty types (`ERR_UNKNOWN_TREATY`).
    - **TC-FREL.9 (Existence Status Guards):** Factions in `in_exile` or `eliminated` are blocked from pairwise war, NAP, and Alliance (`ERR_INVALID_STATUS`); `eliminated` factions are also blocked from signing peace.
    - **TC-FREL.10 (Isolation from Player Diplomacy & Raids):** Pairwise NPC-to-NPC war, peace, NAP, and Alliance leave player-facing `FactionData` fields (`opinion`, `is_at_war`, `has_nap`, `has_alliance`) unchanged, emit zero player-facing `war_declared`/`peace_signed`/`treaty_signed` signals, and schedule zero `BattleCampaignManager` settlement raids.
    - **TC-FREL.11 (Neutral Tribe Ascension Preservation):** When `neutral_tribe` ascends to `emerging_power` (`Liên Minh Rừng Thiêng`), its stable ID `"neutral_tribe"`, canonical pair keys, and existing pairwise wars/NAPs/opinions remain intact.
    - **TC-FREL.12 (Idempotent Initialization & Daily Simulation Preservation):** Calling `initialize_pairwise_relations(false)` or advancing `update_daily_simulation(day)` preserves existing pairwise relationships without resetting them.
    - **TC-FREL.13 (Save/Load Roundtrip):** `SaveManager` serializes and restores `factions.pairwise_relations` across all 3 NPC pairs (Allied, NAP with asymmetric opinions, and At War) with 100% fidelity.
    - **TC-FREL.14 (Legacy Save Compatibility):** Saves omitting `pairwise_relations` pass schema validation and initialize clean neutral pairwise defaults while preserving player-facing faction opinions and `last_diplomacy_days`.
    - **TC-FREL.15 (Double-Load Idempotency):** Consecutive calls to `SaveManager.apply_loaded_state_to_world()` produce identical pairwise relationship states with zero leakage from prior in-memory state.
    - **TC-FREL.16 (Fail-Closed Validation & Completeness):** `SaveManager.validate_save_data()` rejects non-Dictionary `pairwise_relations`, empty `pairwise_relations` (`{}`), missing any of the 3 canonical pair records, self-relations, unknown IDs, non-canonical ordering (`faction_a > faction_b`), mismatched keys, out-of-range opinions (`> 100.0`), `NaN` opinions, non-boolean flags, contradictory war+NAP, and contradictory Alliance-without-NAP before any world mutation, while cleanly accepting valid complete saves and preserving live world state.
  - *Status:* **PASSED** (2026-10-25, Exit Code 0: 16/16 tests passed, 160 checks passed).

### Package 1V: Functional Automation Graph MVP
- **TC-AGRAPH.1 to TC-AGRAPH.16: Automation Graph MVP Verification Suite**
  - *Script:* `res://scripts/test/test_automation_graph.gd`
  - *Acceptance Criteria:*
    - **TC-AGRAPH.1 (Data Model & Serialization):** `AutomationProgram` correctly stores `id`, `name`, `enabled`, `priority`, `nodes`, and `edges`, and roundtrips cleanly through `serialize()` and `deserialize()`.
    - **TC-AGRAPH.2 (Structural Validation):** `AutomationGraphValidator` rejects null programs, empty node graphs, missing trigger nodes, duplicate node IDs, and invalid node types/subtypes.
    - **TC-AGRAPH.3 (Orphan & Reachability Detection):** Graph validator detects orphan/unreachable nodes via BFS and backward data dependency tracing, rejecting disconnected subgraphs while accepting valid flow and condition inputs.
    - **TC-AGRAPH.4 (Socket/Port Compatibility):** Enforces strict port typing; rejects connecting flow outputs (`out`, `true`, `false`) into boolean input sockets (`cond`, `inA`, `inB`) and rejects connecting nodes to themselves.
    - **TC-AGRAPH.5 (Cycle & Infinite Loop Prevention):** Iterative DFS cycle detector rejects cyclic connections fail-closed before runtime execution.
    - **TC-AGRAPH.6 (IfElse Node Constraints):** Requires IfElse nodes to have a valid condition input connected to `cond` and at least one outgoing branch (`true` or `false`).
    - **TC-AGRAPH.7 (Condition Evaluation):** Evaluates `ResourceCompare` (<, <=, >, >=, ==) against stock and gold/treasury, `CitizenFatigue` against citizen thresholds, and `StorageFull` against capacity limits.
    - **TC-AGRAPH.8 (LogicGate Combinations):** Evaluates `AND`, `OR`, and `NOT` gates with single and nested inputs deterministically.
    - **TC-AGRAPH.9 (Runtime IfElse Branching):** Dynamically evaluates condition node and dispatches control flow strictly to the `true` branch or `false` branch.
    - **TC-AGRAPH.10 (Action AssignRole & Guard Guardrails):** Assigns living citizens from `from_role` to `to_role`, prevents duplicate reassignment in the same tick via action locks, and enforces Barracks activity requirement for guard role.
    - **TC-AGRAPH.11 (Action BoostJobPriority & EmitLog):** Calls authoritative `JobManager.boost_jobs_priority()` and writes diagnostic entries to trace and persistent execution logs.
    - **TC-AGRAPH.12 (Execution Step Budget Enforcement):** Strict budget (`MAX_STEPS_PER_RUN = 60`) halts execution safely without freezing or crashing when exceeded.
    - **TC-AGRAPH.13 (Dry Run Immutability Guarantee):** Test/Simulate mode executes side-effect-free, guaranteeing zero mutation to citizen roles, resource stocks, job priorities, or persistent execution logs while returning complete diagnostic trace.
    - **TC-AGRAPH.14 (Priority Ordering & Simulation Pause):** Higher priority programs execute first; simulation pause (`is_paused: true`) halts graph execution completely.
    - **TC-AGRAPH.15 (Save/Load Integration & Legacy Compatibility):** `SaveManager` validates and persists `automation.programs` and `execution_logs`; rejects malformed graphs fail-closed; and seamlessly loads legacy saves lacking the `automation` section without schema bump.
    - **TC-AGRAPH.16 (Preset Rules Non-Regression):** Existing preset rules in `AutomationManager` (food emergency priority boost, buffer congestion, winter preparation) remain 100% operational alongside graph programs.
  - *Status:* **PASSED** (2026-10-25, Exit Code 0: 16/16 tests passed, 69 checks passed).

---

### Fix Package: Responsive Game Window & HUD Layout
- **TC-RESP.1 to TC-RESP.6: Responsive Window, Viewport, HUD & Panels Suite**
  - *Tracked Headless & Standalone Test Suite:* `res://scripts/test/test_responsive_layout.gd` (automated structural assertions and multi-resolution SubViewport runtime bounds assertions)
  - *Developer-Owned Visual Validation Script:* `res://scripts/test/visual_responsive_validation.gd` (untracked, standalone GPU test with PNG screen captures to `docs/visual_validation/` for human inspection)
  - *Execution Modes & Architecture Distinction:*
    - **Standalone OS Window:** Primary production target. Configured in `project.godot` (`viewport_width = 1280`, `viewport_height = 720`, `resizable = true`, `stretch/mode = "canvas_items"`, `stretch/aspect = "expand"`). Enforces minimum OS window size of 1024x576 via `DisplayServer.window_set_min_size()`. Responds to OS window resizing, maximize/restore buttons, and F11 fullscreen toggle (`DisplayServer.WINDOW_MODE_FULLSCREEN`). Canvas items expand responsively, maintaining crisp pixel rendering without black pillarbox/letterbox bars.
    - **Godot Editor Embedded Mode:** In-editor preview runs inside the Godot 4 Editor Game dock (`SubViewportContainer`). Sizing is governed strictly by the Godot Editor Game toolbar modes (`Fixed Size`, `Keep Aspect Ratio`, `Stretch to Fit`, or pop-out window). Native OS window calls (`DisplayServer.window_set_min_size()`, `DisplayServer.window_set_mode()`) do not resize editor dock panels. To view full responsive scaling inside the editor dock, users select `Stretch to Fit` on the Game toolbar, or pop out the Game view to an independent window, or disable `Run > Window Placement > Embed Game in Editor` in Editor Settings.
  - *Acceptance Criteria by Section:*
    - **Section A: Structural & Declared Configuration Assertions**
      - **TC-RESP.1 (ProjectSettings Window & Stretch Configuration):** `project.godot` explicitly configures `viewport_width = 1280`, `viewport_height = 720`, `stretch/mode = "canvas_items"`, and `stretch/aspect = "expand"`. `DisplayServer.window_set_min_size(Vector2i(1024, 576))` API executes cleanly without errors.
      - **TC-RESP.2 (Legacy HUD Node Path Integrity & Backwards Compatibility):** All 8 resource labels (`FoodLabel`, `WoodLabel`, `StoneLabel`, `OreLabel`, `MetalLabel`, `ToolsLabel`, `GoldLabel`, `PopLabel`) maintain exact legacy node paths under `TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/...`, guaranteeing 100% compatibility with existing test suites (`test_mine.gd`, `test_workshop.gd`). Clock and date labels, speed buttons, and all 5 BottomBar buttons maintain their node paths and script bindings.
      - **TC-RESP.3 (TopBar 2-Row Responsive Geometry & Declared Clearance):** `TopBar` height accommodates 2 rows (`offset_bottom >= 64.0`). Row 1 (`TopRow`) combined minimum width is 591px (<= 650px). Row 2 (`Resources`) combined minimum width is 938px (<= 960px). Positive clearance at 1024x576 is 62px (> 40px), guaranteeing zero horizontal clipping or label loss down to minimum resolution.
      - **TC-RESP.4 (BottomBar Responsive Geometry, Declared Clearance & Button Visibility):** `BottomBar` combined minimum width is 726px (<= 750px), providing 274px of clearance at 1024x576. `TileInfoLabel` uses `OVERRUN_TRIM_ELLIPSIS` (3) to prevent label expansion from pushing buttons offscreen. All 5 action buttons (`BuildBtn`, `ResearchBtn`, `DiplomacyBtn`, `MilitaryBtn`, `AutomationBtn`) have custom minimum widths <= 130px, are strictly visible, and remain fully within screen bounds.
      - **TC-RESP.5 (Secondary Panels & Automation Editor Layout Bounds):** `BuildMenuPanel` bottom (-56px) does not penetrate BottomBar top (-48px), preserving 8px clearance. `ResearchMenuPanel` and `DiplomacyPanel` heights (440px) fit cleanly between TopBar (Y=68) and BottomBar (Y=528). `EventBanner` and `CrisisBanner` `offset_top` (76px) are positioned cleanly below TopBar. `AutomationEditor` uses responsive `split_offset = 540`, `RightScroll` (ScrollContainer) with minimum width 280px (<= 300px), and `GraphEdit` canvas with `SIZE_EXPAND_FILL`.
      - **TC-RESP.6 (Isometric Coordinate Transformation Purity Invariance):** `IsoMath.map_to_local` and `local_to_map` roundtrip mapping is 100% invariant across discrete grid cells, verifying mathematical projection purity. (Note: mouse picking under dynamic window resizing additionally depends on camera viewport matrix and display stretch transform).
    - **Section B: Runtime Viewport Bounds & Actual Control Geometry (5 Viewport Resolutions: 1024x576, 1152x648, 1280x720, 1366x768, 1920x1080)**
      - **MainMenu Bounds & Centering:** `MainPanel` has non-empty geometry (`size > (0, 0)`), is strictly enclosed within viewport bounds (`vp_rect.encloses(mp_rect)`), and is horizontally centered (`abs(pos.x - (vp_w - panel_w)/2) <= 1.0`).
      - **TopBar & BottomBar Containment:** Both bars have actual global rects enclosed within viewport; TopBar is anchored at `y = 0.0`; BottomBar bottom edge exactly matches viewport height (`end.y == vp_h`).
      - **Action Button Rectangles:** All 5 buttons (`BuildBtn`, `ResearchBtn`, `DiplomacyBtn`, `MilitaryBtn`, `AutomationBtn`) have non-empty geometry (`size > (0, 0)`), are strictly enclosed within visible viewport bounds, and are contained within BottomBar bounds.
      - **Resource Labels Non-Overflow:** All 8 resource labels have non-empty geometry, and every label's right edge is strictly bounded within the viewport (`end.x <= vp_w`), maintaining positive right-edge safety clearance (>= 40px at 1024x576; 970px at 1920x1080).
      - **Panel Non-Overlap Verification:** When floating panels are active, `BuildMenuPanel`, `ResearchMenuPanel`, and `DiplomacyPanel` have bottom bounds strictly above BottomBar top (`end.y <= bot_bar.pos.y`) and top bounds strictly below TopBar bottom (`pos.y >= top_bar.end.y`), proving zero overlap across all resolutions.
      - **Automation Editor Containment & Usable Child Geometry:** `AutomationEditor` Panel is enclosed within viewport bounds; `GraphEdit` canvas and `RightScroll` inspector have usable non-zero dimensions (`GraphEdit >= (200, 150)`, `RightScroll >= (150, 100)`) and are strictly enclosed within the editor panel.
  - *Status:* **PASSED** (2026-10-25, Exit Code 0: 435/435 checks passed across Section A structural checks and Section B runtime bounds across 5 viewport resolutions).

---

### Package 1W: Tactical Military Units & Command MVP
- **TC-TAC.1 to TC-TAC.30: Tactical Military Units & Command Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_tactical_military.gd`
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_tactical_military.gd`
  - *Acceptance Criteria by Group:*
    - **Group 1: Data & Roster Synchronization (TC-TAC.1 to TC-TAC.7)**
      - **TC-TAC.1 (Initial Empty State):** Clean initialization starts with 0 tactical units and empty selection.
      - **TC-TAC.2 (Recruitment Synchronization):** Recruiting 1 soldier in `PlayerArmyManager` creates exactly 1 `TacticalUnit` actor at rally cell with unique ID.
      - **TC-TAC.3 (Multi-Unit Roster Scaling):** Recruiting multiple soldiers expands the roster 1:1 with unique IDs.
      - **TC-TAC.4 (Signal Idempotency):** Replaying army recruitment signals does not duplicate units.
      - **TC-TAC.5 (Casualty Deduction):** Removing casualties authoritatively synchronizes tactical roster without double deduction.
      - **TC-TAC.6 (Civilian Isolation):** Military unit operations never modify civilian citizen count or roles.
      - **TC-TAC.7 (Economic Integrity):** Barracks capacity and recruitment resource costs remain authoritative and invariant.
    - **Group 2: Tactical Unit Selection (TC-TAC.8 to TC-TAC.12)**
      - **TC-TAC.8 (Single Selection):** Left-clicking a unit selects only that unit and activates its ground selection ring indicator.
      - **TC-TAC.9 (Additive Selection):** Shift+left-click toggles units into or out of selection.
      - **TC-TAC.10 (Screen-Space Drag Selection):** Dragging a viewport rectangle selects enclosed units; dragging in empty space deselects.
      - **TC-TAC.11 (Raycast Layer Separation):** Clicking civilian citizens does not select military units.
      - **TC-TAC.12 (Overlay Layer Isolation):** Selection box operates on dedicated overlay layer without displacing HUD layout.
    - **Group 3: Tactical Movement & Pathfinding (TC-TAC.13 to TC-TAC.20)**
      - **TC-TAC.13 (Single Unit Movement):** Right-click dispatches move order using A* grid navigation; unit transitions to `MOVING` state.
      - **TC-TAC.14 (Out-of-Bounds Movement Rejection):** Orders to out-of-bounds coordinates fail closed with informative reason.
      - **TC-TAC.15 (Unwalkable Terrain Rejection):** Orders to impassable cells fail closed.
      - **TC-TAC.16 (Multi-Unit Collision Avoidance):** Group move orders compute distinct, non-overlapping, walkable destination slots.
      - **TC-TAC.17 (Order Completion):** Units follow waypoint path and transition cleanly to `IDLE` at target cells.
      - **TC-TAC.18 (TimeManager Pause Compliance):** Pausing the simulation freezes tactical movement immediately without coordinate loss.
      - **TC-TAC.19 (TimeManager Speed Scaling):** Simulation speeds (1x, 2x, 3x) scale movement speed cleanly without cell-skipping glitches.
      - **TC-TAC.20 (Order Retasking):** New move orders interrupt and replace active movement paths immediately.
    - **Group 4: Formations & Control Groups (TC-TAC.21 to TC-TAC.25)**
      - **TC-TAC.21 (Formation Slot Geometries):** `Line`, `Column`, and `Scatter` produce valid, distinct, walkable destination slots with zero duplicates.
      - **TC-TAC.22 (Control Group Recall):** Recalling assigned control groups reselects the registered units.
      - **TC-TAC.23 (Keybinding Isolation):** `Ctrl+1/2/3` and `Shift+1/2/3` do not mutate `TimeManager` simulation speed.
      - **TC-TAC.24 (Dead Unit Pruning):** Casualty deductions automatically prune dead units from control groups.
      - **TC-TAC.25 (HUD Integration & Panel Containment):** Tactical command widgets reside within `ArmyPanel` without breaking responsive HUD bounds.
    - **Group 5: Persistence, Save/Load & Integrity (TC-TAC.26 to TC-TAC.30)**
      - **TC-TAC.26 (Tactical State Serialization):** Serializes active formation and unit coordinates faithfully.
      - **TC-TAC.27 (Save & Load Roundtrip):** World state save and load restores exact unit coordinates, formation, and 1:1 count match.
      - **TC-TAC.28 (Load Idempotency):** Consecutive loads restore cleanly with zero duplicate or orphaned units.
      - **TC-TAC.29 (Legacy Save Reconstruction):** Pre-tactical saves without `tactical_military` synthesize a valid roster from `soldier_count` at rally point.
      - **TC-TAC.30 (Fail-Closed Integrity Validation):** Malformed saves (duplicate IDs, count mismatch vs authoritative army, out-of-bounds coords) are rejected fail-closed.
  - *Status:* **PASSED** (2026-10-25, Exit Code 0: 74/74 assertions passed across all 30 test cases).

---

### Package 1W Follow-Up: Occupancy-Safe Tactical Roster, Fail-Closed Save & Strategic/Tactical Consistency
- **FU-CASE.1 to FU-CASE.22: Tactical Integration & Hardening Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_tactical_military.gd` (Group 6)
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_tactical_military.gd`
  - *Acceptance Criteria by Problem Group:*
    - **Group A: Multi-Transaction Spawn & Formation Occupancy Safety (FU-CASE.1 to FU-CASE.10)**
      - **FU-CASE.1 to FU-CASE.3:** Recruited units across sequential transactions occupy strictly unique, pairwise-distinct coordinates with zero coordinate stacking against existing active units or batch units.
      - **FU-CASE.4:** Replaying `army_changed` signal is strictly idempotent with zero coordinate mutation or duplicate spawns.
      - **FU-CASE.5:** Casualties reduce units correctly without mutating civilian citizens.
      - **FU-CASE.6:** `can_allocate_spawns()` verifies spatial availability; over-capacity requests fail closed cleanly without stacking.
      - **FU-CASE.7 & FU-CASE.8:** Moving a selected group when unselected units occupy target cells avoids collision and assigns distinct slots excluding cells occupied by unselected units.
      - **FU-CASE.9 & FU-CASE.10:** Insufficient slots reject orders atomically (all-or-nothing dispatch); `Line`, `Column`, and `Scatter` produce valid non-overlapping slots.
    - **Group B: Fail-Closed Persistence & Legacy Reconstruction Gating (FU-CASE.11 to FU-CASE.17)**
      - **FU-CASE.11:** Valid tactical saves with matching `soldier_count` pass schema validation.
      - **FU-CASE.12:** Saves where `tactical_military.units` is empty while `soldier_count > 0` are rejected fail-closed.
      - **FU-CASE.13 & FU-CASE.14:** Missing `units` field or invalid types in `tactical_military` are rejected before world mutation.
      - **FU-CASE.15:** Pure legacy saves completely lacking `tactical_military` are accepted and reconstruct roster safely.
      - **FU-CASE.16 & FU-CASE.17:** Consecutive loads produce zero duplicates, and serialization roundtrip faithfully preserves units, coordinates, and formation.
    - **Group C & D: Strategic vs Tactical Consistency & Defense/Campaign Gates (FU-CASE.18 to FU-CASE.22)**
      - **FU-CASE.18:** When army is at base within rally perimeter (Manhattan distance <= 5), army is defense-eligible and all garrisoned soldiers count toward settlement defense.
      - **FU-CASE.19:** Deploying part of the force into the field (distance > 5) updates `get_garrisoned_unit_count()` and `get_defending_soldier_count()` to reflect only garrisoned soldiers.
      - **FU-CASE.20:** Strategic commands (`order_move`, `order_return_home`) synchronize tactical unit movements and high-level movement states.
      - **FU-CASE.21:** Offensive campaigns strictly reject launching if the army is garrisoned at base.
      - **FU-CASE.22:** Casualties reduce authoritative soldier count once, and tactical roster stays synchronized without double deduction.
  - *Status:* **PASSED** (2026-10-25, Exit Code 0: 112/112 assertions passed in `test_tactical_military.gd`; all 10 project regression test suites passed with 0 failures).

---

### Package 1W Final Hardening: Field-Only Campaigns, Strict Save Validation & Movement Integrity
- **FH-CASE.1 to FH-CASE.10: Final Hardening Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_tactical_military.gd` (Group 7)
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_tactical_military.gd`
  - *Acceptance Criteria by Fix Category:*
    - **Fix A: Field-Only Offensive Campaigns & Location-Restricted Casualties (FH-CASE.1 to FH-CASE.3)**
      - **FH-CASE.1:** Offensive campaigns strictly reject launching when field troops == 0, even when garrisoned soldier count > 0.
      - **FH-CASE.2:** Split army offensive campaigns use only eligible field units as attacking troop force (`atk_troops = get_field_unit_count()`); casualties deduct strictly from field units (`from_field = true`) and never touch garrisoned base defenders.
      - **FH-CASE.3:** Split army defensive settlement raids deduct casualties strictly from garrisoned defenders (`from_field = false`) and never touch deployed field units.
    - **Fix B: Fail-Closed Persistence & Path Validation (FH-CASE.4 to FH-CASE.8)**
      - **FH-CASE.4:** Strict save validation rejects moving tactical units without a `current_path`.
      - **FH-CASE.5:** Strict save validation rejects moving units whose `current_path` final waypoint does not match `target_cell`.
      - **FH-CASE.6:** Strict save validation rejects idle/holding units with a non-empty `current_path`.
      - **FH-CASE.7:** Strict save validation rejects soldier count mismatches against `player_army.soldier_count` even when `player_army` lacks `movement_state` (removing `is_legacy_army` validation bypass).
      - **FH-CASE.8:** Save restoration fails closed (`apply_loaded_state_to_world` returns `{"success": false}`) on corrupted tactical military data without destroying or mutating live world state (validation-before-mutation).
    - **Fix C: Safe Strategic/Tactical Movement Advancement (FH-CASE.9)**
      - **FH-CASE.9:** Marching units advance cell-by-cell via `advance_movement(delta, speed_mult)` without forced snapping or teleportation (`arrive_all_at_destination()`). Units naturally transition to IDLE upon reaching target cell.
    - **Fix D: Army Count UI Signals (FH-CASE.10)**
      - **FH-CASE.10:** `PlayerArmyManager.remove_casualties()` unconditionally emits `army_changed` signal with accurate post-casualty count when tactical manager is active.
  - *Status:* **PASSED** (2026-10-28, Exit Code 0: 145/145 assertions passed in `test_tactical_military.gd`; all 10 project test suites passed with 0 failures).

### Package 1W Post-Hardening Review & Final Review: Garrison Return, Ready Field Force & Casualty Eligibility
- **PH-CASE.1 to PH-CASE.9 & Hardened FH-CASE: Post-Hardening Review Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_tactical_military.gd` (Group 7 & Group 8)
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_tactical_military.gd`
  - *Acceptance Criteria by Problem Group:*
    - **Fix A: Garrison Return Allocation & Perimeter Containment (PH-CASE.1 to PH-CASE.4, PH-CASE.9)**
      - **PH-CASE.1 (12 Soldiers Return-Home in Line Formation):** 12 soldiers in default Line formation return home through complete process. All 12 units stop moving, occupy pairwise distinct cells, remain strictly within `RALLY_PERIMETER_DISTANCE = 5`, strategic state is `GARRISONED`, defending count equals 12, and subsequent `tactical_state_updated` signals maintain `GARRISONED` with zero drift to `IDLE_AT_FIELD`.
      - **PH-CASE.2 (20 Soldiers Return-Home in Line Formation):** 20 soldiers in default Line formation execute full return-home. All 20 units stop moving on pairwise distinct cells strictly within distance $\le 5`, strategic state remains `GARRISONED`, defending count equals 20, and state does not revert.
      - **PH-CASE.3 (Atomic Rejection on Insufficient Return Slots via Real Dispatcher):** Calls real `TacticalMilitaryManager.order_return_all_to_rally()` with insufficient slots (`RestrictedGarrisonNav`), verifying atomic rejection, positions/states/paths/accumulators unmodified, and unit selection preserved without unintentional `select_all`.
      - **PH-CASE.4 (Strategic Wrapper Failure Propagation & Route Invariance):** Tests `PlayerArmyManager.order_return_home()` with valid strategic path but trapped tactical unit (`TrappedTacticalUnitNav`). Confirms fail-closed tactical failure propagation, zero partial orders issued, strategic state preserved as `IDLE_AT_FIELD`, and verifies reissued command preserves routes and accumulators.
      - **PH-CASE.9 (Repeated-Command Return-Home Regression):** Strategic center reaches `rally_cell` before individual tactical units. Confirms state remains `MARCHING` in transit; reissuing `order_return_home()` succeeds without resetting `step_accumulator` or stalling units; units complete movement to pairwise distinct cells $\le 5$ distance; strategic state transitions to `GARRISONED` only upon full arrival and remains stable across subsequent signals.
    - **Fix B: Ready Field Troops & Offensive Gate Consistency (PH-CASE.5 & PH-CASE.6, Hardened FH-CASE.2)**
      - **FH-CASE.2 Hardened:** Verifies battle report produced $\ge 1$ player casualties (`attacker_casualties >= 1`), proving non-vacuous casualty deduction strictly from the field cohort while garrison units are untouched.
      - **PH-CASE.5 (Moving Field Subset Excluded from Attacking Cohort):** When a field subset is moving, only stationary field units outside perimeter count as ready field troops (`get_field_unit_count() == 2`). `can_launch_offensive_campaign()` and `launch_offensive_campaign()` strictly use ready stationary troops (`atk_troops == 2`); moving field units and base garrison units take zero casualties.
      - **PH-CASE.6 (Zero Ready Field Troops Blocks Offensive Campaign):** When all field units are moving mid-march, `get_field_unit_count() == 0` and offensive campaign is rejected fail-closed.
    - **Fix C: Defensive vs. Offensive Casualty Predicate Consistency (PH-CASE.7 & PH-CASE.8, Dedicated FH-CASE.3)**
      - **FH-CASE.3 Dedicated:** Dedicated split-army fixture explicitly asserting pre-raid counts $> 0$ (2 garrison, 2 field, 1 moving at base). Exercises live `resolve_and_apply_raid()`, verifying $\ge 1$ defender casualties deducted strictly from base defenders while field units and moving units remain untouched, and tactical roster size matches soldier count.
      - **PH-CASE.7 (Defensive Casualty Predicate Matches Defense Eligibility):** A moving unit inside base perimeter is never removed as a defensive casualty; the stationary defender is removed. Roster size strictly matches soldier count.
      - **PH-CASE.8 (Field Casualty Predicate Matches Field Eligibility):** A moving field unit is never removed as a field casualty; base garrison units are untouched; the stationary field unit is removed.
    - **Fix D: Real Gameplay & Persistence Paths (Hardened FH-CASE.8b)**
      - **FH-CASE.8b:** Verifies `SaveManager.apply_loaded_state_to_world()` reports failure on corrupted tactical military data without destroying live world state.
  - *Status:* **PASSED** (2026-10-29, Exit Code 0: 252/252 assertions passed in `test_tactical_military.gd`).

### Package 1W Garrison Transition Audit: Strict Invariant Enforcement & Integrated Restore
- **GTA-CASE.1 to GTA-CASE.7: Strict Garrison Transition Audit Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_tactical_military.gd` (Group 9)
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_tactical_military.gd`
  - *Acceptance Criteria by Case:*
    - **GTA-CASE.1 (Cancel Move While Tactical Units In Transit & Field Settlement):** Strategic center at `rally_cell` in `MARCHING` state with empty path; at least one tactical unit in transit (`order_state == MOVING`, distance 6 > 5). `cancel_move()` executes without entering `GARRISONED`, strictly preserving `MARCHING` in-transit state and unit path. Advancing simulation transitions to `GARRISONED` only after all units are idle and within distance $\le 5$. Sub-check: when unit is stopped outside perimeter (dist > 5), `cancel_move()` cleanly yields `IDLE_AT_FIELD` and strictly avoids `GARRISONED`.
    - **GTA-CASE.2 (Cancel Move When Already Settled at Base):** Strategic center at `rally_cell` with all tactical units idle within perimeter $\le 5$. `cancel_move()` transitions cleanly to `GARRISONED` with zero unit displacement, unchanged roster size, and valid defending count.
    - **GTA-CASE.3 (Route-Recovery & Integrated Save Restore Invariant):**
      - **GTA-CASE.3A (Dynamic Route Obstruction Reroute Failure):** Strategic army at `rally_cell` with tactical unit moving. Dynamic obstacle causes rerouting failure; recovery halts strategic center but strictly preserves `MARCHING` without prematurely marking non-empty army `GARRISONED`.
      - **GTA-CASE.3B (Integrated Restore with Moving Tactical Unit):** Save data specifies `player_army.movement_state: "garrisoned"` while `tactical_military` contains a moving unit. Following integrated world restore via `SaveManager.apply_loaded_state_to_world()`, restored strategic state is strictly corrected to `MARCHING`, never retaining a false `GARRISONED` status.
      - **GTA-CASE.3C (Integrated Restore with Field Tactical Unit):** Save data specifies `player_army.movement_state: "garrisoned"` while `tactical_military` contains an idle unit at `(42, 42)` (dist > 5). Restored strategic state is strictly corrected to `IDLE_AT_FIELD`.
    - **GTA-CASE.4 (Direct deserialize() with Moving Tactical Unit):** Direct `PlayerArmyManager.deserialize()` with `movement_state: "garrisoned"` while attached `TacticalMilitaryManager` has a moving unit. Strictly does NOT publish `GARRISONED`; immediately sets and emits `MARCHING` reflecting the in-transit unit.
    - **GTA-CASE.5 (Direct deserialize() with Idle Unit Outside Perimeter):** Direct `deserialize()` with `movement_state: "garrisoned"` while attached tactical roster has an idle unit at distance 19 > 5. Strictly does NOT publish `GARRISONED`; immediately sets and emits `IDLE_AT_FIELD`.
    - **GTA-CASE.6 (Empty Tactical Roster Fail-Closed Invariant):**
      - **Part A:** `are_all_tactical_units_settled_at_base()` strictly returns `false` when roster is empty for `soldier_count > 0`.
      - **Part B:** Direct `deserialize()` with empty roster strictly refuses `GARRISONED` and sets tentative `IDLE_AT_FIELD`.
      - **Part C:** `sync_state_from_tactical()` immediately clears any existing `GARRISONED` state and transitions to `IDLE_AT_FIELD` when `soldier_count > 0` and roster is empty.
      - **Part D:** `SaveManager.validate_save_data()` strictly fails closed (`valid: false`) on saves with empty tactical units when `soldier_count > 0`.
    - **GTA-CASE.7 (Genuine Zero-Soldier Army Normalization):**
      - **Part A:** `are_all_tactical_units_settled_at_base()` returns `true` for 0 soldiers with 0 units.
      - **Part B:** Direct `deserialize()` normalizes genuine 0-soldier army to `GARRISONED` at `rally_cell`.
      - **Part C:** Integrated save validation and application restores 0-soldier army as `GARRISONED` cleanly.
    - **GTA-CASE.8 (Missing Tactical Manager with Positive Soldier Count):**
      - **Part A:** `are_all_tactical_units_settled_at_base()` returns `false` when `tactical_military_mgr == null` and `soldier_count > 0`.
      - **Part B:** `get_settled_state_for_cell(rally_cell)` strictly refuses `GARRISONED` and yields safe `IDLE_AT_FIELD`.
      - **Part C:** `sync_state_from_tactical()` immediately clears `GARRISONED` and sets `IDLE_AT_FIELD` when manager is null.
      - **Part D:** Direct `deserialize()` strictly refuses `GARRISONED` and sets safe `IDLE_AT_FIELD` when manager is null.
      - **Part E:** `_arrive_at_destination()` at `rally_cell` sets `IDLE_AT_FIELD` (never `GARRISONED`) when manager is null.
    - **GTA-CASE.9 (Tactical Roster Count Mismatch Fail-Closed):**
      - **Part A:** `are_all_tactical_units_settled_at_base()` returns `false` when roster count differs from `soldier_count`.
      - **Part B:** `get_settled_state_for_cell()` returns `IDLE_AT_FIELD` on count mismatch.
      - **Part C:** `sync_state_from_tactical()` clears `GARRISONED` and sets `IDLE_AT_FIELD` on count mismatch.
      - **Part D:** `SaveManager.validate_save_data()` strictly rejects count mismatch fail-closed (`valid: false`).
    - **GTA-CASE.10 (Zero-Soldier Exception with Missing Manager):**
      - **Part A:** `are_all_tactical_units_settled_at_base()` returns `true` for genuine 0-soldier army even when manager is null.
      - **Part B:** `get_settled_state_for_cell()` yields `GARRISONED` at `rally_cell` for genuine 0 soldiers.
      - **Part C:** `sync_state_from_tactical()` normalizes 0-soldier army to `GARRISONED` at `rally_cell`.
    - **GTA-CASE.11 (State Transitions & Return-Home Command Audit):**
      - **Part A:** `order_return_home()` when tactical units are stationary outside perimeter (or manager is missing/mismatched) transitions to safe `IDLE_AT_FIELD` via `get_settled_state_for_cell()`, returning action `idle_at_rally` and strictly avoiding false `GARRISONED` or fabricated `MARCHING`.
      - **Part B:** Casualty reduction to 0 soldiers (`remove_casualties`) immediately normalizes strategic army to `GARRISONED` at `rally_cell` and synchronizes tactical roster to 0 units.
    - **GTA-CASE.12 (Recruitment Without Tactical Manager):**
      - **Part A:** `can_recruit()` is strictly read-only with zero mutations to `movement_state`, `current_cell`, or `current_path`.
      - **Part B:** Field deployment check `if current_cell != rally_cell:` correctly allows base recruitment when army is at `rally_cell` without a manager (`IDLE_AT_FIELD`), while strictly blocking recruitment when army is away in the field.
      - **Part C:** `recruit()` atomic resource deduction operates cleanly; upon recruitment with missing tactical manager, army state normalizes to `IDLE_AT_FIELD` at `rally_cell` (never `GARRISONED`), strictly preventing false garrison status without a roster.
    - **GTA-CASE.13 (Direct deserialize({}) and Active Ghost Unit Cleanup):**
      - Direct `PlayerArmyManager.deserialize({})` calls `tactical_military_mgr.clear_all_units()`, cleanly destroying active moving tactical units and resetting state to 0 soldiers/0 units `GARRISONED` at `rally_cell` without orphaned ghost actors.
    - **GTA-CASE.14 (Symmetric Detachment, Ghost Unit Cleanup & Re-attachment Lifecycle):**
      - **Part A:** Recruited 2 soldiers with attached tactical manager (`fu_tac.get_unit_count() == 2`, `GARRISONED`).
      - **Part B:** Detaching manager (`fu_army.set_tactical_military_manager(null)`) symmetrically clears back-reference (`fu_tac.player_army_mgr == null`), unbinds signals, cleans roster (0 ghost units), and transitions army to `IDLE_AT_FIELD`.
      - **Part C:** Recruitment while detached succeeds (`soldier_count == 3`), detached manager produces zero rogue units (`fu_tac.get_unit_count() == 0`), and army remains `IDLE_AT_FIELD`.
      - **Part D:** Re-attaching manager (`fu_army.set_tactical_military_manager(fu_tac)`) restores back-reference, reconstructs authoritative roster (`fu_tac.get_unit_count() == 3`), and cleanly restores `GARRISONED`.
      - **Part E:** Reverse detachment from manager side (`fu_tac.set_player_army_manager(null)`) symmetrically clears `player_army_mgr`, cleans roster, unbinds signals, and transitions army to `IDLE_AT_FIELD`.
    - **GTA-CASE.15 (Zero-Soldier Shortcut Emptiness Verification):**
      - Zero-soldier shortcut in `get_settled_state_for_cell()` and `sync_state_from_tactical()` refuses `GARRISONED` and returns `IDLE_AT_FIELD` when stale units remain in the tactical manager.
  - *Status:* **PASSED** (2026-10-29, Exit Code 0: 385/385 assertions passed in `test_tactical_military.gd`).

---

### Package 1X: Tactical Combat, Enemy Military AI & Field Siege
- **TC-COMBAT.1 to TC-COMBAT.11: Real-Time Tactical Combat Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_tactical_combat.gd`
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_tactical_combat.gd`
  - *Acceptance Criteria:*
    - **TC-COMBAT.1 (Combat Stat Initialization):** Tactical units initialize with `health = 100.0`, `max_health = 100.0`, `attack_damage = 25.0`, `attack_range = 1`, `attack_cooldown = 1.2`, `attack_cooldown_remaining = 0.0`, `is_alive = true`, and `faction_id = 'player'`.
    - **TC-COMBAT.2 (Take Damage & Damage Indicator):** `take_damage(amount, attacker_id)` reduces health, emits `unit_took_damage(unit_id, amount, attacker_id)`, triggers visual damage flash timer, and preserves life when `health > 0`.
    - **TC-COMBAT.3 (Lethal Damage & Defeat Signal):** Overkill damage clamps health to 0.0, sets `is_alive = false`, emits `unit_defeated(unit_id, killer_id)`, returns unit to `OrderState.IDLE`, and dead units ignore further damage.
    - **TC-COMBAT.4 (Friendly Fire Rejection):** Tactical units cannot attack units of the same faction (`faction_id == 'player'`); cross-faction attacks are accepted.
    - **TC-COMBAT.5 (Order Attack & Target Assignment):** Right-click or `order_attack(target)` transitions unit to `OrderState.ATTACKING` and sets `target_actor` and `target_actor_id`.
    - **TC-COMBAT.6 (Range Checking & Strike Resolution):** Manhattan distance check (`grid_distance <= attack_range`) allows melee attacks without displacement; dealing damage applies to target and triggers attack cooldown.
    - **TC-COMBAT.7 (Cooldown Enforcement):** Zero damage is dealt while `attack_cooldown_remaining > 0.0`; cooldown decrements each frame and allows next strike only upon reaching 0.0.
    - **TC-COMBAT.8 (TimeManager Pause & Speed Scaling):** Combat cooldown and strike progress freeze strictly when paused; 2x/3x speed scales strike progression proportionally.
    - **TC-COMBAT.9 (Dead Target Auto-Disengage):** Defeating or losing the target node automatically resets `order_state` to `OrderState.IDLE`, clearing `target_actor` and `target_actor_id`.
    - **TC-COMBAT.10 (Strict Casualty Parity with PlayerArmyManager):** Defeating player tactical units decrements `PlayerArmyManager.soldier_count` 1:1, cleans defeated units from the roster, and normalizes a depleted army (0 soldiers) to `GARRISONED` at `rally_cell`.
    - **TC-COMBAT.11 (Combat Serialization Roundtrip):** Serializes and deserializes all combat properties (`health`, `max_health`, `attack_damage`, `attack_range`, `attack_cooldown`, `is_alive`, `faction_id`, `target_actor_id`) faithfully.
  - *Status:* **PASSED** (2026-10-29, Exit Code 0: 58/58 assertions passed).

- **TC-ENEMY.1 to TC-ENEMY.11: Enemy Military Entities & Tactical AI Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_enemy_military_ai.gd`
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_enemy_military_ai.gd`
  - *Acceptance Criteria:*
    - **TC-ENEMY.1 (Visuals & Modulate):** `EnemyTacticalUnit` inherits from `TacticalUnit` and displays crimson modulate `Color(0.95, 0.3, 0.3, 1.0)`, detection range 8 tiles, and starts in `ACQUIRE_TARGET`.
    - **TC-ENEMY.2 (Spawning API & Identification):** `EnemyMilitaryManager.spawn_enemy_unit()` generates stable IDs (`enemy_unit_1`), sets owning faction, places at cell, emits `enemy_spawned`, and updates roster count.
    - **TC-ENEMY.3 (Force Spawning on Distinct Slots):** `spawn_enemy_force()` allocates distinct, non-overlapping walkable cells around the spawn center without tile stacking.
    - **TC-ENEMY.4 (Targeting & Deterministic Tie-Breaking):** Selects closest player unit; equal Manhattan distance ties broken by lexicographical ascending unit ID order.
    - **TC-ENEMY.5 (AI State Machine Transitions):** Unit transitions between `ACQUIRE_TARGET` -> `PURSUE` (when distance > attack_range) -> `ATTACK` (when distance <= attack_range) -> `PURSUE` dynamically.
    - **TC-ENEMY.6 (Deterministic Iteration Order):** `EnemyMilitaryManager.advance_simulation()` processes units strictly in ascending sorted key order.
    - **TC-ENEMY.7 (Peace Treaty Cessation):** Signing a peace treaty immediately halts attack orders, transitions AI to `RECOVER_RETREAT`, and paths units back to retreat coordinates.
    - **TC-ENEMY.8 (Defeat Cleanup):** Defeated enemy emits `enemy_defeated` on manager and is immediately removed from the active enemy roster.
    - **TC-ENEMY.9 (Serialization Roundtrip):** Serializes and deserializes enemy units, stats, coordinates, and owning factions accurately.
    - **TC-ENEMY.10 (Patrol Area Recovery & Perimeter Return):** Units outside `patrol_radius` calculate path back toward `patrol_origin` and transition to `MOVING`; trapped units gracefully fall back to `HOLD`.
    - **TC-ENEMY.11 (Atomic Fail-Closed Enemy Deserialization):** Corrupted enemy save records fail validation before clearing live roster, preserving pre-existing units intact.
  - *Status:* **PASSED** (2026-10-29, Exit Code 0: 54/54 assertions passed).

- **TC-SIEGE.1 to TC-SIEGE.13: Field Siege Operations & Victory Conditions Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_field_siege.gd`
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_field_siege.gd`
  - *Acceptance Criteria:*
    - **TC-SIEGE.1 (Objective Actor Lifecycle):** `SiegeObjectiveActor` initializes with ID, owning faction, 300.0 durability, `is_alive = true`, `is_captured = false`, and garrison defender count.
    - **TC-SIEGE.2 (Outpost Durability, Active Siege Gating & Capture):** Health reductions require `is_under_active_siege == true`; taking damage emits `objective_damaged`; reaching 0.0 HP sets `is_alive = false`, `is_captured = true`, and emits `objective_destroyed` and `objective_captured`. Damage calls before active siege return early without taking damage.
    - **TC-SIEGE.3 (Eligibility Gating):** Rejects when player has 0 field troops, when not at war, when faction is inactive, or when player army is too far from the objective; accepts when assembled field troops are in proximity.
    - **TC-SIEGE.4 (Launch & Defender Mobilization):** `launch_field_siege()` emits `field_siege_started` and mobilizes garrison defenders on distinct walkable cells around the outpost. Sets `is_under_active_siege = true`.
    - **TC-SIEGE.5 (Victory Resolution & Plunder Awards):** Capturing the objective resolves siege as `VICTORY`, emits `field_siege_resolved`, reduces faction military power (-20), and awards plunder (+60 Gold, +40 Food, +20 Metal). Resets `is_under_active_siege = false`.
    - **TC-SIEGE.6 (Defeat Resolution):** Total wipeout of attacking field forces resolves siege as `DEFEAT`.
    - **TC-SIEGE.7 (Withdrawal Resolution):** Retreating field troops back to base perimeter resolves siege as `WITHDRAWAL`.
    - **TC-SIEGE.8 (Coexistence with Battle Campaigns):** `FieldSiegeManager` operations and objectives coexist cleanly with `BattleCampaignManager` without mutating offensive sequence counters.
    - **TC-SIEGE.9 (Siege Serialization Roundtrip):** Serializes and deserializes active siege objectives and operational status with fail-closed schema validation.
    - **TC-SIEGE.10 (Atomic Fail-Closed Deserialization):** Staged validation verifies all records before clearing live state; invalid objectives or sieges return `false` without corrupting live instances.
    - **TC-SIEGE.11 (Real ResourceManager Integration & Canonical Stock):** Plunder rewards deposit into real `ResourceManager` storage, clamped strictly by warehouse capacity.
    - **TC-SIEGE.12 (Tactical Attack Order Gating):** Tactical attack orders on inactive outpost targets are rejected fail-closed with localized reason code.
    - **TC-SIEGE.13 (Peace Treaty Siege Cancellation):** Peace treaty cancels active sieges against the faction and resets objective siege status.
    - **TC-SIEGE.14 (Siege Retry Idempotency & Bounded Defender Replenishment):** Launching a siege spawns initial defenders; defeating one defender, withdrawing, and retrying replenishes only the missing defender up to `garrison_count` rather than spawning duplicate full waves; subsequent retry with full garrison spawns 0 new units.
    - **TC-SIEGE.15 (Exact Objective Cell Prioritization & Zero Objective Overlap):** Guaranteed zero spawned units occupy the objective cell; direct clicks on the objective cell prioritize the outpost over adjacent enemy units.
  - *Status:* **PASSED** (2026-10-29, Exit Code 0: 85/85 assertions passed).

- **TC-INT.1 to TC-INT.8: Package 1X Gameplay Integration Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_package_1x_gameplay_integration.gd`
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_package_1x_gameplay_integration.gd`
  - *Acceptance Criteria:*
    - **TC-INT.1 (WorldView Outpost Initialization):** Deterministic outpost registration creates exactly one objective per active faction at walkable cells > 15 distance from player rally, avoiding buildings and obstacles.
    - **TC-INT.2 (War Declaration & Idempotent Spawning):** `FactionManager.war_declared` triggers idempotent hostile force mobilization around the faction's outpost. Repeated events do not duplicate defenders.
    - **TC-INT.3 (Right-Click Siege Gating & Launch):** Ineligible right-clicks (inactive siege, army not assembled/nearby) show HUD banner and reject attack orders; eligible right-clicks launch siege, mobilize defenders, and issue attack orders.
    - **TC-INT.4 (Combat, Objective Capture & Canonical Plunder):** Units engage defenders and outpost; destroying outpost triggers `VICTORY`, deposits +60 Gold, +40 Food, +20 Metal bounded by storage.
    - **TC-INT.5 (Peace Declaration Cessation & Retreat):** `FactionManager.peace_signed` disengages player units, cancels active sieges, and commands enemy forces to retreat cleanly.
    - **TC-INT.6 (Save/Load Persistence & Double-Load Idempotency):** Complete WorldView roundtrip serializes and restores outposts, enemy forces, and active sieges; repeated load produces 100% identical state without duplication.
    - **TC-INT.7 (Authoritative Spawn-Slot Entity Exclusion):** Verifies that all active enemy units are in bounds, occupy walkable cells, are not on water tiles, do not overlap building footprints, and strictly exclude objective cells, player tactical units, and living citizens.
    - **TC-INT.8 (End-to-End Siege Retry Lifecycle & Anti-Inflation):** Tests live WorldView war declaration, siege launch, withdrawal, and retry, verifying that retrying does not inflate defenders beyond `garrison_count`, and repeated war declarations preserve exact unit counts.
  - *Status:* **PASSED** (2026-10-29, Exit Code 0: 57/57 assertions passed).

---

### Package 1Y: Automation Graph Delay & Repeat Nodes
- **TC-Y.1 to TC-Y.36: Automation Graph Delay & Repeat Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_automation_graph_delay_repeat.gd`
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_automation_graph_delay_repeat.gd`
  - *Acceptance Criteria by Group:*
    - **Group 1: Delay Node Validation & Bounds (1–720h) (TC-Y.1 to TC-Y.2)**
      - **TC-Y.1 (Valid Durations):** Accepts integer durations 1, 24, and 720 hours.
      - **TC-Y.2 (Invalid Durations & Missing Edge Rejection):** Rejects fail-closed invalid durations (0, -5, 721, 9999, floats, strings, null) and Delay nodes lacking an outgoing `out` port.
    - **Group 2: Delay Runtime Progression & Simulation Clock (TC-Y.3 to TC-Y.8)**
      - **TC-Y.3 (Execution Suspension & Scheduling):** Execution halts at Delay; downstream action is not executed immediately; exactly 1 continuation scheduled.
      - **TC-Y.4 (Exact Simulation Hour Resumption):** Verifies scheduled `due_day`, `due_hour`, and `due_total_hours`; continuation does not execute before due hour and executes cleanly on the exact target hour.
      - **TC-Y.5 (Minimum 1h Next-Hour Execution):** A 1h delay scheduled at hour $H$ does not resume at hour $H$; it resumes on the next eligible simulation hour $H+1$.
      - **TC-Y.6 (Pause Compliance):** Paused simulation freezes continuation processing even if simulation time has advanced; resumes cleanly when unpaused.
      - **TC-Y.8 (Cross-Day Boundary Transitions):** Scheduling a delay across midnight accurately calculates `due_day` (Day 2) and `due_hour` without off-by-one errors.
    - **Group 3: Delay Continuation Lifecycle & Safety (TC-Y.9 to TC-Y.12)**
      - **TC-Y.9 (Pre-Delay vs Post-Delay Actions):** Pre-delay actions execute initially; continuation resumption executes strictly post-delay actions (skipping triggers and pre-delay actions).
      - **TC-Y.10 (Single Execution Guarantee):** Resumed continuations are atomically removed from the pending queue and cannot re-execute.
      - **TC-Y.11 (Queue Limits & Fail-Closed Protection):** Schedules up to 10 continuations per program; 11th continuation is rejected with `LIMIT_PROGRAM`.
      - **TC-Y.12 (Program Deletion & Disabled State):** Deleting a program purges all its pending continuations; disabling a program safely skips continuation resumes without errors.
    - **Group 4: Repeat Validation & Iterations (TC-Y.13 to TC-Y.17)**
      - **TC-Y.13 (Valid Counts & Structure):** Accepts integer counts 1, 5, and 20; rejects 0, -1, 21, 100, floats, strings, null, and Repeat nodes without a `body` connection.
      - **TC-Y.14 (Finite Loop Execution):** Body actions execute exactly $N$ times.
      - **TC-Y.15 (Completed Post-Loop Flow):** Downstream nodes connected to the `completed` port execute once all iterations finish.
      - **TC-Y.16 (Acyclicity Enforcement):** Back-edges into Repeat nodes are strictly rejected by the graph validator cycle detector.
      - **TC-Y.17 (Budget Safety & Step Capping):** Combined steps across all iterations increment the global step counter and halt cleanly if `MAX_STEPS_PER_RUN = 60` is exceeded.
    - **Group 5: Editor Ports & Dry-Run Simulation (TC-Y.19 to TC-Y.22)**
      - **TC-Y.19 (Palette Integration):** Palette contains `AddDelayBtn` and `AddRepeatBtn`; clicking adds corresponding nodes.
      - **TC-Y.20 (Slot & Port Mapping):** Verifies port mapping: Delay (`in`: 0, `out`: 0), Repeat (`in`: 0, `body`: 0, `completed`: 1).
      - **TC-Y.22 (Side-Effect-Free Dry Run):** Dry run outputs trace simulation logs detailing expected continuation resume hours and iteration steps without modifying citizen roles, resources, or queuing persistent continuations.
    - **Group 6: SaveManager Persistence & Schema Compatibility (TC-Y.23 to TC-Y.27)**
      - **TC-Y.23 (Continuations Serialization Roundtrip):** Serialized data contains `pending_continuations`; SaveManager accepts valid schema; restored queue preserves `due_day`, `due_hour`, and `due_total_hours`.
      - **TC-Y.24 (Double-Load Idempotency):** Consecutive loads restore the exact continuation queue with zero duplicates.
      - **TC-Y.26 (Malformed Record Fail-Closed Validation):** Rejects invalid types, empty IDs, missing fields, out-of-bounds hours, and negative days fail-closed.
      - **TC-Y.27 (Legacy Save Compatibility):** Saves without `pending_continuations` pass validation and load cleanly with an empty queue under schema version 1.
    - **Group 7: Non-Regression & WorldView Integration (TC-Y.28 to TC-Y.30)**
      - **TC-Y.28 (Preset Rules Preservation):** Preset priority rules (e.g. food emergency) boost jobs properly.
      - **TC-Y.29 (evaluate_rules Backward Compatibility):** Calling `evaluate_rules` without explicit day/hour parameters functions seamlessly.
      - **TC-Y.30 (WorldView Integration):** `WorldView` initializes `automation_mgr` and feeds simulation clock into hourly graph evaluation ticks.
    - **Group 8: Repeat/Delay Interaction, Nested Repeat Prevention & Strict Persistence Gating (TC-Y.31 to TC-Y.37)**
      - **TC-Y.31 (Hour-by-Hour Repeat + Delay Lifecycle):** Executing a 2-iteration loop with an embedded Delay suspends execution upon encountering Delay without prematurely executing subsequent iterations or the `completed` branch. Simulation clock advancement resumes iteration 1 post-delay actions at Hour 8, schedules iteration 2 delay, and Hour 10 resumes iteration 2 post-delay actions, runs completed branch once, with zero premature or duplicate executions.
      - **TC-Y.32 (Save/Load During Delayed Repeat):** Serializing world state while a Repeat loop is suspended on Delay preserves complete continuation metadata (`repeat_node_id`, `repeat_iteration`, `repeat_count`, `steps_used`). Restoration resumes seamlessly across save boundaries, and repeated loading is strictly idempotent with zero duplicate continuations.
      - **TC-Y.33 (Fresh Condition Evaluation Across Repeat Iterations):** Condition nodes evaluated in Repeat loops evaluate freshly per iteration (`iter_memo_bool`), ensuring role or resource changes in iteration 1 correctly influence branching in iteration 2 without stale memoized bleed.
      - **TC-Y.34 (Nested Repeat Fail-Closed Graph Validation):** `AutomationGraphValidator` traverses Repeat body branches and rejects nested Repeat nodes fail-closed with clear diagnostic error.
      - **TC-Y.35 (Strict Fail-Closed Continuation Validation in SaveManager):** Rejects continuation records with duplicate IDs, nonexistent programs, missing resume nodes, invalid delay node IDs, inconsistent due times (`due_total_hours != (due_day - 1) * 24 + due_hour`), non-Repeat target nodes for repeat continuations, iteration > count, steps > budget, global queue limit > 50, or per-program queue limit > 10.
      - **TC-Y.36 (Atomic Staged Deserialization in AutomationManager):** Corrupted or malformed save data fails validation before mutating live state; live programs and pending continuations remain completely intact.
      - **TC-Y.37 (Complete Repeat Continuation Metadata Enforcement):** Enforces all-or-nothing Repeat metadata (`repeat_node_id`, `repeat_iteration`, `repeat_count`, `steps_used`); detects Delay nodes structurally belonging to Repeat bodies via BFS graph reachability; rejects continuations inside Repeat bodies omitting Repeat metadata; rejects continuations referencing unrelated Repeat nodes; rejects continuations whose `resume_node_id` is not an actual downstream target of `delay_node_id`; and preserves compatibility for normal Delay continuations outside Repeat bodies (with or without optional `steps_used`).
  - *Status:* **PASSED** (2026-10-31, Exit Code 0: 179/179 assertions passed across all 37 requirements in Groups 1–8).

---

### Package 1Z: Legacy Fund & Meta-Progression Foundation
- **TC-1Z.1 to TC-1Z.15: Legacy Profile, Persistence, Exactly-Once Claims & Integration Test Suite**
  - *Tracked Test Suite:* `res://scripts/test/test_legacy_fund.gd`
  - *Command:* `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --path "e:\KINGDOMS UNBOUND\kingdoms-unbound" -s res://scripts/test/test_legacy_fund.gd`
  - *Acceptance Criteria by Scenario:*
    - **Scenario 1 (Authoritative Profile Initialization):** Clean profile initializes with `profile_id: "legacy_profile_default"`, `legacy_balance: 0`, `lifetime_legacy_earned: 0`, `lifetime_legacy_spent: 0`, empty `claimed_rewards`, and empty `unlocked_achievements`.
    - **Scenario 2 (Schema Validation — Valid Data):** Successfully validates correct profile structure satisfying both mathematical invariants: `legacy_balance == earned - spent` and `sum(claimed_rewards) == earned`.
    - **Scenario 3 (Fail-Closed on Negative Balances):** Rejects profile data containing negative `legacy_balance`, `lifetime_legacy_earned`, or `lifetime_legacy_spent`.
    - **Scenario 4 (Fail-Closed on Balance Invariant Tampering):** Rejects profile data where `legacy_balance != earned - spent`.
    - **Scenario 5 (Fail-Closed on Claimed Rewards Sum Mismatch):** Rejects profile data where `sum(claimed_rewards.amount) != lifetime_legacy_earned`.
    - **Scenario 6 (Fail-Closed on Invalid Reward Source):** Rejects profile records containing unapproved sources (e.g. cheat or injection attempts); accepts only `["victory", "achievement"]`.
    - **Scenario 7 (Fail-Closed on Invalid Reward Amounts):** Rejects non-integer or <= 0 reward amounts.
    - **Scenario 8 (Atomic Persistence & Backup Recovery):** Saving creates atomic `.tmp` and rotates existing target to `.bak`. When primary `.json` is corrupted, automatically recovers cleanly from `.bak`. When both primary and `.bak` are corrupted, fails closed without zeroing or wiping live in-memory state.
    - **Scenario 9 (Exactly-Once Reward Claim API):** Valid first claim succeeds, awards points, increments balance & earned, and atomically persists to disk.
    - **Scenario 10 (Double-Claim Exploit Prevention):** Re-claiming an already claimed `reward_id` is rejected (`already_claimed`), awards 0 points, and preserves balance.
    - **Scenario 11 (Multi-World Victory Claim):** Distinct worlds with unique `world_id`s (`world_alpha`, `world_beta`) can each claim their victory reward once (+100 points each, balance becomes 200). Duplicate claim attempts for an existing world are rejected.
    - **Scenario 12 (Older Save Reload Exploit Prevention):** Reloading an older world save where victory is reached again cannot duplicate rewards because `VictoryManager` verifies existing claims with authoritative `LegacyProfileManager`.
    - **Scenario 13 (Achievement Foundation & Single-Award Invariant):** Seeded `prosperity_victory` achievement can be unlocked once without direct points (`reward_legacy: 0`, deferred to victory claim per FIX-1Z-A). Subsequent unlock attempts across any world are rejected with `already_unlocked`.
    - **Scenario 14 (Deferred Surplus Treasury Conversion):** Extension point `convert_surplus_treasury()` returns `status: "deferred"`, `converted: false`, 0 points awarded, 0 gold deducted.
    - **Scenario 15 (UI & Victory Claim Reflection):** Verifies that `VictoryManager.is_reward_claimable()` logic transitions seamlessly from true to false and reflects accurately in HUD and Main Menu displays.
    - **Expanded Test 1 (Double Reward Elimination — FIX-1Z-A):** Complete prosperity victory grants exactly 100 Legacy Fund total across victory claim and achievement unlock (not 200).
    - **Expanded Test 2 (Achievement Persistence Failure Rollback — FIX-1Z-B):** Simulates disk save failure during `unlock_achievement()`; verifies complete in-memory rollback of achievement unlock, claimed rewards, and balances.
    - **Expanded Test 3 (Profile Initialization Failure Unavailable — FIX-1Z-D):** Corrupted profile + corrupted backup leaves profile unavailable (`is_available() == false`, status `STATUS_UNAVAILABLE`) and does not delete or wipe corrupt files to 0.
    - **Expanded Test 4 (Claims Rejected While Profile Unavailable — FIX-1Z-D):** Both `claim_reward` and `unlock_achievement` return clear `profile_unavailable` errors when profile is unavailable without mutating balances.
    - **Expanded Test 5 (Identical Seeds Have Distinct World IDs — FIX-1Z-C):** Successive calls to `WorldView.generate_unique_world_id()` with identical seed values produce distinct IDs, eliminating seed-based claim collision.
    - **Expanded Test 6 (World ID Persistence on Save / Load — FIX-1Z-C):** World ID is serialized in save file metadata, verified on load, and legacy saves lacking `world_id` are automatically migrated and persisted to disk.
    - **Expanded Test 7 (Unpersisted Migration Prevents Unsafe Claims — FIX-1Z-C):** When world ID migration fails to persist to disk (`is_world_id_persisted == false`), victory claims are strictly gated fail-closed.
    - **Expanded Test 8 (Atomic Write Failure and Rollback):** Disk save failure during `claim_reward` triggers complete rollback of claimed reward records and balances.
    - **Expanded Test 9 (Float / NaN / Inf Rejection Fail-Closed):** Rejects NaN, Inf, non-integer floats, and negative reward amounts fail-closed in both `claim_reward()` and `validate_profile_data()`.
    - **Expanded Test 10 (Failed Operations Leave State Unchanged):** Balance, earned points, spent points, and claimed records remain strictly invariant after rejected claim attempts.
    - **Expanded Test 11 (Canonical Reward ID Enforcement — FIX-1Z-E):** Prosperity victories strictly enforce canonical reward IDs (`victory_<world_id>`). Passing arbitrary custom reward IDs to `claim_legacy_reward()` is ignored/rejected, preventing duplicate claims or exploit cycling.
    - **Expanded Test 12 (Safe Backup Recovery & Corrupt Primary Protection — FIX-1Z-F & FIX-1Z-H):** Profile successfully recovers from valid `.bak` when primary file is corrupt. Subsequent `save_profile()` calls never overwrite the valid backup with corrupt data. Read-back `.tmp` validation and write error checking verified fail-closed.
    - **Expanded Test 13 (SaveManager Atomic Writes & Backup Safety — FIX-1Z-G):** `SaveManager.save_dict_to_file()` writes atomically via `.tmp`, checks directory access and write/flush errors, verifies backup creation before target removal, cleans up temporary files, and restores from backup on rename errors.
    - **Expanded Test 14 (HUD Reward Status Classification — FIX-1Z-I):** Verifies that `InGameHUD._refresh_victory_claim_state()` accurately distinguishes all 6 independent gating and claim states: already claimed ("Đã Nhận Di Sản"), profile unavailable ("Hồ Sơ Lỗi (Không Thể Nhận)"), unpersisted world ("Chưa Lưu Thế Giới"), invalid world ID ("ID Thế Giới Không Hợp Lệ"), claimable ("Nhận Di Sản (+100)"), and unmet conditions ("Chưa Đạt Điều Kiện").
    - **Expanded Test 15 (Numeric Overflow Protection — FIX-1Z-J):** Enforces 64-bit integer limits (`MAX_SAFE_INT = 9223372036854775807`), rejecting any claim amounts or schema records that would overflow `legacy_balance`, `lifetime_legacy_earned`, or claimed reward sums.
  - *Status:* **PASSED** (2026-10-31, Exit Code 0: 30/30 tests passed).
