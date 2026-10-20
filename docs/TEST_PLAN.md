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
    - **TC-DIPLO.1 (Offensive Campaign Opinion Penalty):** A successful player-led offensive campaign applies exactly the configured penalty (-8.0, `OPINION_PENALTY_OFFENSIVE_CAMPAIGN`) to the target faction's opinion. The returned campaign context dictionary contains `diplomatic_opinion_penalty`, `new_opinion`, and `disposition`.
    - **TC-DIPLO.2 (Settlement Raid Opinion Penalty):** A successfully resolved settlement raid applies exactly the configured penalty (-10.0, `OPINION_PENALTY_SETTLEMENT_RAID`) to the attacking faction's opinion. The returned raid context contains `diplomatic_opinion_penalty`, `new_opinion`, and `disposition`.
    - **TC-DIPLO.3 (Boundary Clamping):** Opinion penalties strictly clamp at lower (-100.0) and upper (100.0) boundaries. Starting at -95.0 with a -8.0 or -10.0 penalty clamps exactly to -100.0 without underflow. Further battles at -100.0 remain strictly at -100.0.
    - **TC-DIPLO.4 (Signal Emission Exactly Once):** Exactly one `FactionManager.relation_changed` signal is emitted per successful battle consequence (offensive campaign or settlement raid), with matching payload (`id`, `opinion`, `disposition`).
    - **TC-DIPLO.5 (Fail-Closed Rejection Immutability):** Ineligible offensive campaigns (0 soldiers, garrisoned at base/rally, actively marching, non-war faction, 0 enemy military power) fail closed, causing zero opinion or disposition mutation and emitting zero signals.
    - **TC-DIPLO.6 (Raid Eligibility Immutability):** Raids that are not yet due, already processed for the day, or non-existent fail closed, applying zero diplomatic mutation and emitting zero signals.
    - **TC-DIPLO.7 (Hostile Disposition During War):** While at war (`is_at_war == true`), faction disposition remains strictly locked to `Disposition.HOSTILE` regardless of intermediate opinion values.
    - **TC-DIPLO.8 (Post-Peace Disposition Recalculation):** Signing peace clears war status, applies the peace opinion boost (+20.0), and triggers dynamic recalculation of disposition from post-battle opinion via `FactionData.recalculate_disposition()`: hostile for opinion <= -40.0, neutral for -40.0 < opinion < 25.0, friendly for opinion >= 25.0.
    - **TC-DIPLO.9 (SaveManager Persistence & Double-Load Idempotency):** Live `WorldView` battle results serialize cleanly through `SaveManager.serialize_world_state()` with intact faction opinions and dispositions. Calling `SaveManager.apply_loaded_state_to_world()` accurately restores post-battle opinions and dispositions with zero signal emissions. A second consecutive load executes idempotently with zero opinion mutations, zero signal emissions, and zero duplicated markers.
    - **TC-DIPLO.10 (Combat Mechanics Integrity):** Casualties, military power deductions, plunder, raid schedules, and campaign sequences operate identically alongside diplomatic consequence application.
    - **TC-DIPLO.11 (Diplomacy Regression Suite):** Existing non-aggression pacts, gifts, war declarations, and peace treaties continue to function with full behavioral fidelity and correct signal emission.
  - *Status:* **PASSED** (2026-10-20, Exit Code 0: 11/11 tests passed).
