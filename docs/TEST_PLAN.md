# KINGDOMS UNBOUND — Master Test Plan & Verification Strategy

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
  - *Acceptance Criteria:* Demonstrates 32×16 diamond terrain, multi-tile building with visible roof/facade, isometric tree props, 1 moving citizen with feet pivot at $(12, 30)$, diamond hover highlight, and flawless Y-sorting behind/in front of structures.
  - *Status:* Pending Phase 1.

### Phase 2: Authoritative Resource Ledger & Building Placement
- **TC-2.1: Resource Ledger Conservation & Reservations**
  - *Acceptance Criteria:* Resources cannot be double-spent; reservations lock stock; cancelling releases stock.
  - *Status:* Pending Phase 2.
- **TC-2.2: Building Cost Deductions & Invalid Placement Rejection**
  - *Acceptance Criteria:* Placement on occupied or out-of-bounds tiles rejected; costs deducted exactly once.
  - *Status:* Pending Phase 2.

### Phase 3: Citizens & Grid Navigation
- **TC-3.1: A* Pathfinding Walkability & Blocked Target Recovery**
  - *Acceptance Criteria:* Citizens navigate around obstacles; unreachable targets fail gracefully without infinite loop.
  - *Status:* Pending Phase 3.
- **TC-3.2: 24 Citizen Spawn & Job Distribution**
  - *Acceptance Criteria:* Exactly 24 unique citizen IDs; 5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle.
  - *Status:* Pending Phase 3.

### Phase 4: Logistics & Automation Loop
- **TC-4.1: Physical Hauling vs Teleportation**
  - *Acceptance Criteria:* Produced goods remain in workplace buffer until hauled; storehouse updates only on deposit.
  - *Status:* Pending Phase 4.
- **TC-4.2: Winter Food Deficit & Starvation Escalation**
  - *Acceptance Criteria:* Farm output halves in winter; 0 food does not instantly kill; health drops 5%/day.
  - *Status:* Pending Phase 4.

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
  - *Status:* Pending Phase 6.
- **TC-6.2: Trade Atomic Transaction**
  - *Acceptance Criteria:* Trades succeed all-or-nothing; cannot generate duplicate currency.
  - *Status:* Pending Phase 6.

### Phase 7: Victory & Collapse
- **TC-7.1: Prosperity Victory 5-Day Hold Duration**
  - *Acceptance Criteria:* Victory triggers only after 120 continuous game-hours satisfying all conditions; timer resets on lapse.
  - *Status:* Pending Phase 7.
- **TC-7.2: Collapse Grace Period & Explanatory Output**
  - *Acceptance Criteria:* Town Hall destruction provides 3-day countdown before trigger; summary outputs cause.
  - *Status:* Pending Phase 7.

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
