# TEST COVERAGE GAP ANALYSIS — KINGDOMS UNBOUND (REVISED V2)

- **Date:** 2026-11-07 · **Committed Baseline HEAD:** `4a99322a6d2efb6bc269914f68d2968734d4b678`
- **Test Corpus:** 53 tracked test suites under `scripts/test/test_*.gd`, extending `SceneTree`, run headlessly via `godot --headless -s res://scripts/test/<suite>.gd`.

---

## 1. Test Evidence Hierarchy & Verification Ladder

To maintain absolute documentation integrity, the repository enforces a strict four-level evidence ladder:

| Evidence Level | Implementation in Repo | Evidence Character & Limitations |
|:---|:---:|:---|
| **Level 1: Headless Unit & Subsystem Tests** | **Extensive (53 suites)** | Tests isolated managers in memory, often injecting mock state (`_custom_*`). Proves internal mathematical and state-machine contracts, but bypasses scenes, input handling, and UI. |
| **Level 2: Headless Scene Integration Tests** | **Moderate** | Instantiates real scene nodes (`world_view.tscn`, `tactical_unit.tscn`) headlessly and injects synthetic input events (e.g., `test_world_view_siege_input.gd`, `test_live_battle_loop.gd`, `test_package_1x_gameplay_integration.gd`). Proves full scene wiring and input-to-feedback propagation. |
| **Level 3: Automated Visual/GUI Harnesses** | **Untracked in `scratch/`** | Visual validation runners (`visual_*_validation.gd`) render views to off-screen buffers and save PNG screenshots (26 files under `docs/visual_validation/`). Proves layout, responsive scaling, and rendering correctness. |
| **Level 4: Natural Unassisted Gameplay Acceptance** | **Partial (Documented in WORKLOG)** | Human or unassisted agent gameplay through standard interactive window sessions. Proves emergent game balance and real user experience. Distinct from automated scripts. |

---

## 2. Test Execution Integrity: Regex Word Counting vs Process Exit Codes

A critical discovery of this audit concerns existing untracked regression scripts (e.g., `scratch/run_parse_fix_regression.ps1`):
1. **The Flaw:** Untracked PowerShell scripts aggregate test results by grepping log output for the strings `"PASS"` and `"FAIL"`.
2. **False Failure Reporting:** In `test_army_equipment.gd`, test logs containing the string `"fail-closed"` (asserting that a security/validation check rejected bad input as designed) were counted by the regex as `FailCount: 6`, despite the suite exiting cleanly with code 0!
3. **False Assertion Counts:** In `test_factions_and_battles.gd`, the regex counted 15 lines, whereas the suite actually executed 48 comprehensive assertions.
4. **Authoritative Standard:** All future testing and reporting must rely strictly on **process exit codes (`0` for PASS, non-zero for FAIL)** and the suite's own internal summary lines, completely abandoning regex word counting.

---

## 3. Test Coverage Gaps Status

### GAP-001 — WorldView field-siege attack-order failure handling test
- **Status:** **CLOSED (RESOLVED in Commit `4a99322`)**
- **Committed Suite:** `scripts/test/test_world_view_siege_input.gd` (193 lines, 30 checks, Exit Code 0).
- **Verification Scope:** Instantiates real `world_view.tscn`, injects a `TacticalMilitaryManager` double to force attack-order failure, sends synthetic right-click mouse input with `target_cell` metadata, asserts red failure banner (`Lệnh Tấn Công Thất Bại`), rejects false success feedback, preserves active siege for retry, prevents duplicate siege records, and verifies withdrawal cleanup.

### GAP-002 — Absence of a tracked, exit-code-based regression runner
- **Status:** **CLOSED (RESOLVED in Batch 2)**
- **Tracked Runner:** `scripts/test/run_regression.ps1`
- **Features & Verification:**
  - Sequences through 58 tracked test suites in separate child processes.
  - Abandons regex word counting in favor of strict process exit codes (`$LASTEXITCODE`).
  - Measures execution duration per suite and aggregates total runtime.
  - Enforces explicit baseline classification: recognizes `test_player_army.gd` Exit Code 1 with `TC-ARMY.32` failure signature as `EXPECTED_BASELINE_FAILURE` (`BASELINE-001` / `ISSUE-006`), and any other failure as `UNEXPECTED_FAILURE`.
  - Outputs structured terminal logs and saves machine-readable `regression_summary.json`.
  - Includes `-SelfTest` fixture validation (4/4 fixtures PASS, Exit Code 0).

### GAP-003a — Missing unit test for hauler cargo conservation (`BUG-001`)
- **Status:** **CLOSED (RESOLVED in Batch 2)**
- **Committed Suite:** `scripts/test/test_hauler_death_cargo_conservation.gd` (12/12 checks PASS, Exit Code 0).
- **Verification Scope:** Verifies hauler cargo recovery upon citizen death, idempotency of death signal, storage capacity bounding, and durable pending death cargo recovery across day rollover when central storage is fully saturated.

### GAP-003b — Missing unit test for job lifecycle pruning bounds (`BUG-002`)
- **Status:** **CLOSED (RESOLVED in Batch 2)**
- **Committed Suite:** `scripts/test/test_job_lifecycle_pruning.gd` (10/10 checks PASS, Exit Code 0).
- **Verification Scope:** Proves terminal non-recurring jobs (`COMPLETED`, `CANCELLED`) are pruned from active `_jobs`, recurring jobs loop back to `AVAILABLE`, bounded terminal history ring buffer (50), iterator safety, and 1,000-cycle stress test confirming bounded array size.

### GAP-003c — Missing unit test for autosave vs manual save slot isolation (`BUG-003`)
- **Status:** **CLOSED (RESOLVED in Batch 2)**
- **Committed Suite:** `scripts/test/test_save_slot_isolation.gd` (10/10 checks PASS, Exit Code 0).
- **Verification Scope:** Verifies manual save writes strictly to manual slot (`world_save.json`), daily autosave writes strictly to dedicated autosave slot (`autosave.json`), independent `.bak` backup rotation, and UI restore actions.

### GAP-004 — High coupling to private internals in test suites
- **Status:** **OPEN**
- **Risk:** Over 480 instances of direct access to private fields (`._variable`) exist across test suites. While effective for fine-grained verification, this creates brittle tests that break on internal refactoring even when public APIs remain stable.

### GAP-005 — Normal gameplay acceptance evidence untracked
- **Status:** **OPEN / PARTIALLY ADDRESSED**
- **Current State:** The Package 2J entry in `docs/WORKLOG.md` explicitly distinguishes automated headless PASS from PARTIAL ACCEPTANCE for natural gameplay. However, structured human-readable acceptance checklists remain untracked.

### GAP-006 — Absence of a tracked all-scripts parse check
- **Status:** **CLOSED (RESOLVED in Batch 2)**
- **Tracked Validator:** `scripts/test/test_all_scripts_load.gd`
- **Verification:** Headlessly iterates `res://scripts/` recursively, loading all 124 `.gd` files into memory to verify syntax validity, symbol resolution, and absence of `const` ClassDB shadowing. Confirmed 124/124 scripts compiled and loaded cleanly (Exit Code 0).

### GAP-007 — Baseline simulation runner fails without environment isolation
- **Status:** **DOCUMENTED / ISOLATION RECIPE STANDARDIZED**
- **Root Cause & Recipe:** `scripts/test/test_simulation_baseline_runner.gd` enforces a fail-closed preflight check requiring `$env:APPDATA` to contain `"sim_isolation"` or `"test"` to prevent overwriting player profiles.
- **Authoritative Execution Recipe:**
  ```powershell
  $isoDir = "$PSScriptRoot/../../scratch/sim_isolation"
  New-Item -ItemType Directory -Force -Path $isoDir | Out-Null
  $oldAppData = $env:APPDATA
  try {
      $env:APPDATA = $isoDir
      & "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s res://scripts/test/test_simulation_baseline_runner.gd -- --seed=12345 --speed=3 --target_hours=24
  } finally {
      $env:APPDATA = $oldAppData
  }
  ```

---

## 4. Known Baseline Limitation (`BASELINE-001` / `TC-ARMY.32`)

- **Suite:** `scripts/test/test_player_army.gd`
- **Result:** `[FAIL] TC-ARMY.32: Damaged barracks still provides capacity: 5` (Exit Code 1).
- **Integrity Rule:** In accordance with project rules, this failure must always be reported as a pre-existing baseline limitation inherited from Package 2F (`docs/KNOWN_ISSUES.md` `ISSUE-006`). It must never be obscured, silenced by modifying test assertions, or misreported as a new regression.
