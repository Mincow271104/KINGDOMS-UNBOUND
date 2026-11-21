# Wildlife Save/Load — Final Read-Only Verification Report

**Date:** 2026-11-15
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`
**Target Fix Report:** `docs/reports/WILDLIFE_SAVE_LOAD_REGRESSION_FIX_REPORT.md`
**Scope:** Final read-only verification of the Defect D-01 Save/Load fix (`WANDERING`, `FLEEING`, and `BEING_HUNTED` normalization) prior to commit approval. No production, test, scene, asset, or configuration files were modified.

---

## 1. Verification Scope

Verified:
- `Case 9k` in `scripts/test/test_wildlife_natural_movement.gd` and threat-scan timing in `scripts/world/wildlife_manager.gd`.
- Exact file-change attribution using Git status, file timestamps, and session edit records.
- Production fix scope in `scripts/world/wildlife_manager.gd`.
- Accuracy of `docs/reports/WILDLIFE_SAVE_LOAD_REGRESSION_FIX_REPORT.md` against current source and test files.

---

## 2. Git Branch and Working-Tree Status

- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Wildlife & report untracked (`??`) entries (`git status --short scripts/world/wildlife* scripts/test/test_wildlife* docs/reports/`):**
  - `?? docs/reports/`
  - `?? scripts/test/test_wildlife_ecosystem.gd` (`.uid`)
  - `?? scripts/test/test_wildlife_natural_movement.gd` (`.uid`)
  - `?? scripts/world/wildlife_actor.gd` (`.uid`)
  - `?? scripts/world/wildlife_config.gd` (`.uid`)
  - `?? scripts/world/wildlife_manager.gd` (`.uid`)
- Nothing is staged, committed, or pushed.

---

## 3. Case 9k Verification (Exact Code & Test Evidence)

Inspected `scripts/test/test_wildlife_natural_movement.gd:278-282`:
```gdscript
var threat_unit := {"current_cell": loaded_rabbit["cell"] + Vector2i(1, 0), "is_alive": true}
mgr_reg._threat_scan_accum = WildlifeManager.THREAT_SCAN_INTERVAL
mgr_reg.advance_simulation(0.05, 1.0, wd, nav, [], [threat_unit])
_assert(int(loaded_rabbit["state"]) == WildlifeConfig.BehaviorState.FLEEING and loaded_rabbit["threat_cell"] == threat_unit["current_cell"], "Case 9k: Normal fleeing works with valid threat after load")
```

Verification against all 7 criteria:
1. **Loaded state:** `loaded_rabbit` was loaded into normalized `IDLE` (`Case 9f`), then simulated for up to 80 steps in `Case 9j` (without threats, so it may be `IDLE` or `WANDERING`, never `FLEEING`).
2. **Valid nearby threat:** `threat_unit` is placed 1 cell away (`loaded_rabbit["cell"] + Vector2i(1, 0)`), within `rabbit`'s `awareness_radius = 4`, with `"is_alive": true`.
3. **Threat visibility:** `advance_simulation()` (`wildlife_manager.gd:207-210`) reads Dictionary entries in `player_units` with `is_alive == true` and `current_cell is Vector2i`.
4. **Real `THREAT_SCAN_INTERVAL` mechanism:** **Partially bypassed / primed.** Line 280 explicitly sets `mgr_reg._threat_scan_accum = WildlifeManager.THREAT_SCAN_INTERVAL` (`0.25`) instead of letting `_threat_scan_accum` accumulate naturally over `0.25s` of simulation ticks.
5. **No direct state forcing:** The test does **not** set `loaded_rabbit["state"] = FLEEING`; `advance_simulation()` (`wildlife_manager.gd:229-243`) executes the real threat-detection branch and sets `rec["state"] = FLEEING` and `rec["threat_cell"] = nearest_threat`.
6. **Resulting state:** Asserted `FLEEING`.
7. **Resulting `threat_cell`:** Asserted equal to `threat_unit["current_cell"]`.

---

## 4. Whether the Real Threat Scan Interval Is Exercised

- The threshold condition (`_threat_scan_accum >= THREAT_SCAN_INTERVAL` at `wildlife_manager.gd:198`) and the threat-detection body (`lines 200-243`, including resetting `_threat_scan_accum = 0.0`) **are** executed.
- However, elapsed-time accumulation up to `THREAT_SCAN_INTERVAL` (`0.25s`) is **not** exercised in `Case 9k` because `_threat_scan_accum` is primed directly at line 280.

---

## 5. Exact File-Change Attribution and Evidence Limitations

Because all wildlife files are untracked (`??`) in Git, `git diff` cannot independently show pre-fix vs. post-fix lines. Attribution combines Git status, NTFS `LastWriteTime` timestamps, and session edit records:

| File | Timestamp | Attribution | Evidence |
| :--- | :--- | :--- | :--- |
| `scripts/world/wildlife_manager.gd` | `2026-11-15 14:32:34` | **Confirmed modified during this fix** | Session `edit_file` record + timestamp matching fix pass; Git shows `??`. |
| `scripts/test/test_wildlife_natural_movement.gd` | `2026-11-15 14:32:45` | **Confirmed modified during this fix** | Session `edit_file` record + timestamp matching fix pass; Git shows `??`. |
| `docs/reports/WILDLIFE_SAVE_LOAD_REGRESSION_FIX_REPORT.md` | `2026-11-15 14:33:54` | **Confirmed created during this fix** | Session `write_file` record + timestamp; Git shows `?? docs/reports/`. |
| `scripts/world/wildlife_config.gd` | `2026-11-15 14:17:19` | **Pre-existing untracked file** | Timestamp predates fix pass; untouched. |
| `scripts/world/wildlife_actor.gd` | `2026-11-15 14:17:26` | **Pre-existing untracked file** | Timestamp predates fix pass; untouched. |
| `scripts/test/test_wildlife_ecosystem.gd` | `2026-11-15 05:13:16` | **Pre-existing untracked file** | Timestamp predates fix pass; untouched. |

*(Limitation: Without a prior Git commit for `scripts/world/wildlife*`, independent Git diff attribution is unavailable.)*

---

## 6. Production Fix Scope Verification

Verified directly in `scripts/world/wildlife_manager.gd`:
- `serialize()` (`lines 758-760`): Normalizes `BEING_HUNTED`, `WANDERING`, and `FLEEING` to `IDLE`.
- `deserialize_or_init()` (`lines 806-808`): Normalizes `BEING_HUNTED`, `WANDERING`, and `FLEEING` to `IDLE` on load.
- Unchanged: Species movement parameters, gait/animation logic, non-Save/Load state transitions, Monster / Phase 9 files, user saves, and unrelated project files.

---

## 7. Existing Implementation Report Accuracy

Compared `docs/reports/WILDLIFE_SAVE_LOAD_REGRESSION_FIX_REPORT.md` against current source and test files:
- Exact file paths, function names (`serialize()`, `deserialize_or_init()`), line ranges (`758-760`, `806-808`), normalization logic, test case names (`Case 9d`–`Case 9l`), assertion counts (`73/73`, `36/36`, `33/33`, `182/182`, `1076/1076`, `127/127`), Git status, and user-save/commit statements are accurate.
- No tests were rerun during this read-only verification task.

---

## 8. Report Corrections Made

None required (`docs/reports/WILDLIFE_SAVE_LOAD_REGRESSION_FIX_REPORT.md` was left unchanged).

---

## 9. Confirmed Defects or Remaining Risks

- **Confirmed defects:** None remaining for D-01.
- **Minor test risk:** `Case 9k` primes `_threat_scan_accum` directly rather than advancing `0.25s` of simulation time.
- **Unverified:** Live D3D12 graphical viewport inspection (only `--headless` tests were run in the prior implementation pass).

---

## 10. Final Verdict

**PASS WITH WARNINGS**
*(D-01 normalization fix in `serialize()` and `deserialize_or_init()` is verified correct and narrowly scoped; warnings reflect that `Case 9k` primes `_threat_scan_accum` directly and untracked `??` Git status limits independent diff attribution.)*

---

## 11. Read-Only Confirmation

Confirmed: **No** production code, test code, scenes, assets, or configuration files were modified during this verification. Only `docs/reports/WILDLIFE_SAVE_LOAD_FINAL_VERIFICATION_REPORT.md` was created.

---

## 12. Git Commit/Push Confirmation

Confirmed: **No** `git add`, `git commit`, or `git push` occurred.
