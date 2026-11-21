# Wildlife Save/Load — Targeted Regression Fix Report

**Date:** 2026-11-15
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`
**Audit Reference:** `docs/reports/WILDLIFE_NATURAL_MOVEMENT_READ_ONLY_AUDIT.md` (Defect **D-01**)
**Scope:** Targeted Save/Load state-normalization fix in `WildlifeManager` (`scripts/world/wildlife_manager.gd`) and focused regression tests in `scripts/test/test_wildlife_natural_movement.gd`.

---

## 1. Original Defect D-01 and Verified Root Cause

- **Defect D-01 (High):** In `scripts/world/wildlife_manager.gd`, `serialize()` (`lines 758-760`) previously normalized only `BehaviorState.BEING_HUNTED` to `IDLE`, saving `BehaviorState.WANDERING` (`1`) and `BehaviorState.FLEEING` (`2`) as-is without persisting `target_cell`, `move_progress`, `burst_remaining`, or `threat_cell`.
- On load, `deserialize_or_init()` (`lines 806-809`) passed the saved state into `_make_animal_record()`, which initialized `target_cell = cell`, `move_progress = 0.0`, and `threat_cell = Vector2i(-1, -1)`.
- In `advance_simulation()` (`lines 255-319`), `if rec["target_cell"] != rec["cell"]` was skipped (`target_cell == cell`), and the at-cell-center state machine (`lines 281-319`) handled only `IDLE`, `ALERT`, `DEFENSIVE_DISPLAY`, and `FLEEING`—with **no** `WANDERING` branch. Consequently, any animal saved in `WANDERING` became permanently stationary in `WANDERING` after load (`bird` and `frog` forever since `awareness_radius == 0`), and `FLEEING` animals loaded with an invalid `threat_cell = Vector2i(-1, -1)`.

---

## 2. Exact Files Changed

| File | Change Summary |
| :--- | :--- |
| `scripts/world/wildlife_manager.gd` | Normalized `WANDERING` and `FLEEING` alongside `BEING_HUNTED` to `IDLE` in both `serialize()` and `deserialize_or_init()`. |
| `scripts/test/test_wildlife_natural_movement.gd` | Added regression cases `Case 9d`–`Case 9l` (9 assertions) verifying `WANDERING`/`FLEEING`/`BEING_HUNTED` Save/Load normalization, resumed movement, post-load fleeing with valid threat, and 6-species integrity. |
| `docs/reports/WILDLIFE_SAVE_LOAD_REGRESSION_FIX_REPORT.md` | Created this implementation report. |

---

## 3. Exact Functions and Logic Modified

1. **`WildlifeManager.serialize()` (`scripts/world/wildlife_manager.gd:758-760`):**
   - Changed:
     ```gdscript
     if st == WildlifeConfig.BehaviorState.BEING_HUNTED:
         st = WildlifeConfig.BehaviorState.IDLE
     ```
     to:
     ```gdscript
     if st == WildlifeConfig.BehaviorState.BEING_HUNTED or st == WildlifeConfig.BehaviorState.WANDERING or st == WildlifeConfig.BehaviorState.FLEEING:
         st = WildlifeConfig.BehaviorState.IDLE
     ```
2. **`WildlifeManager.deserialize_or_init()` (`scripts/world/wildlife_manager.gd:806-808`):**
   - Changed:
     ```gdscript
     if st_val == WildlifeConfig.BehaviorState.BEING_HUNTED:
         st_val = WildlifeConfig.BehaviorState.IDLE
     ```
     to:
     ```gdscript
     if st_val == WildlifeConfig.BehaviorState.BEING_HUNTED or st_val == WildlifeConfig.BehaviorState.WANDERING or st_val == WildlifeConfig.BehaviorState.FLEEING:
         st_val = WildlifeConfig.BehaviorState.IDLE
     ```

---

## 4. Chosen Recovery Strategy for `WANDERING`

- **Strategy:** Normalize `BehaviorState.WANDERING` to `BehaviorState.IDLE` in **both** `serialize()` and `deserialize_or_init()`.
- **Rationale:**
  - Restores every loaded wandering animal to a consistent stationary state (`state == IDLE`, `target_cell == cell`, `move_progress == 0.0`, staggered `state_timer` via `_make_animal_record()`), preserving its logical `cell`, `home_cell`, and species parameters without altering live in-game movement.
  - Normalizing in `deserialize_or_init()` as well ensures older save files already containing `"state": 1` (`WANDERING`) also recover cleanly.
  - Preserves canonical `Save -> Load -> Save` equivalence in `test_save_load.gd`.

---

## 5. Chosen Recovery Strategy for `FLEEING`

- **Strategy:** Normalize `BehaviorState.FLEEING` to `BehaviorState.IDLE` in **both** `serialize()` and `deserialize_or_init()`.
- **Rationale:**
  - `threat_cell` is transient and not persisted in the Save/Load schema (`version: 2`). Normalizing `FLEEING` to `IDLE` prevents loaded animals from remaining in `FLEEING` with `threat_cell == Vector2i(-1, -1)`.
  - If a valid threat is still nearby after load, the normal `THREAT_SCAN_INTERVAL` check in `advance_simulation()` immediately re-triggers `FLEEING` with a valid live `threat_cell`.

---

## 6. Regression Test Cases Added (`scripts/test/test_wildlife_natural_movement.gd`)

Added `Case 9d`–`Case 9l`:
- `Case 9d`: Fixture locating `bird`, `rabbit`, and `deer` in loaded manager.
- `Case 9e`: Save `bird` mid-step in `WANDERING` (`target_cell != cell`, `move_progress = 0.45`); load; verify `state == IDLE`, `target_cell == cell`, `move_progress == 0.0`.
- `Case 9f`: Save `rabbit` in `FLEEING`; load; verify `state == IDLE` and `threat_cell == Vector2i(-1, -1)`.
- `Case 9g`: Save `deer` in `BEING_HUNTED`; load; verify `state == IDLE`.
- `Case 9h` & `Case 9i`: Inject raw `"state": WANDERING` and `"state": FLEEING` directly into saved payload and call `deserialize_or_init()`; verify both normalize to `IDLE` with cleared `threat_cell`.
- `Case 9j`: Advance simulation on loaded `bird`; verify it resumes normal wandering (`cell` changes or `target_cell != cell`).
- `Case 9k`: Place a nearby threat unit next to loaded `rabbit` and advance simulation; verify normal `FLEEING` triggers with valid `threat_cell`.
- `Case 9l`: Verify all 6 species (`bird`, `frog`, `rabbit`, `deer`, `wild_boar`, `mountain_goat`) remain present and valid after Save/Load.

---

## 7. Exact Test Commands and Actual Results

All tests ran headless with isolated temporary `APPDATA` (`$env:TEMP\ku_test_appdata_wl`):

```powershell
$env:APPDATA = Join-Path $env:TEMP "ku_test_appdata_wl"
$godot = "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe"
$proj = "e:\KINGDOMS UNBOUND\kingdoms-unbound"

& $godot --headless --path $proj --script "res://scripts/test/test_wildlife_natural_movement.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_wildlife_ecosystem.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_cookhouse_closure.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_save_load.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_hunter_closure.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_fog_of_war_reconnaissance.gd"
```

---

## 8. Existing Test Suites Executed and Results

- `test_wildlife_natural_movement.gd`: **73 passed, 0 failed** (up from 64 with 9 new Save/Load regression assertions)
- `test_wildlife_ecosystem.gd`: **36 passed, 0 failed**
- `test_cookhouse_closure.gd`: **33 passed, 0 failed**
- `test_save_load.gd`: **182 passed, 0 failed**
- `test_hunter_closure.gd`: **1076 passed, 0 failed**
- `test_fog_of_war_reconnaissance.gd`: **127 passed, 0 failed**

---

## 9. Git Branch and Working-Tree Status

- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Before fix (`git status --short scripts/world/wildlife* scripts/test/test_wildlife* docs/reports/`):**
  - `?? docs/reports/`
  - `?? scripts/test/test_wildlife_ecosystem.gd` (`.uid`)
  - `?? scripts/test/test_wildlife_natural_movement.gd` (`.uid`)
  - `?? scripts/world/wildlife_actor.gd` (`.uid`)
  - `?? scripts/world/wildlife_config.gd` (`.uid`)
  - `?? scripts/world/wildlife_manager.gd` (`.uid`)
- **After fix:** Same untracked wildlife/report entries; no unrelated files were modified, and nothing was staged, committed, or pushed.

---

## 10. Remaining Limitations / Unverified Behavior

- Live D3D12 graphical viewport inspection was not executed (all checks ran `--headless`).

---

## 11. Confirmation

Confirmed: **No** real user saves were modified (isolated `APPDATA` was used for all test runs), **no** Monster or unrelated files were changed, and **no** `git add`, `git commit`, or `git push` occurred.
