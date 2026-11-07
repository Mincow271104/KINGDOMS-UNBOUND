# KINGDOMS UNBOUND — Known Issues & Technical Resolutions

## Active Issues

### ISSUE-006: Pre-Existing test_player_army.gd TC-ARMY.32 Baseline Limitation
- **Severity:** Low / Baseline Test Limitation
- **Symptom:** `scripts/test/test_player_army.gd` test case `TC-ARMY.32` fails with assertion error when testing building damage state.
- **Root Cause:** Package 2F (commit `a55021c`) restricted `WorldView.set_building_state()` to valid operational transitions (`"paused"` and `"active"`). `TC-ARMY.32` was written prior to Package 2F and calls `set_building_state(b_id, "damaged")`, which is rejected by `WorldView`.
- **Architectural Scope Isolation:** In accordance with Stage F of the Package 2J audit, Package 2J is strictly scoped to Army Equipment Progression and does not absorb unrelated fixes for building state management (preserving `TC-ARMY.32` as an intentional baseline failure). For Package 2J integration hygiene, `scripts/world/world_view.gd` was modified to correctly display a red error banner when `issue_attack_order()` fails after a field siege launch (Package 2J Field Siege failure path) and to resolve shadowed GDScript variable warnings in upgrade and workshop construction routines.
- **Status:** Documented baseline issue to be addressed in subsequent building maintenance tasks.

---

## Resolved Issues

### ISSUE-007: Hauler Cargo Destroyed on Citizen Death (Resolved in Post-2J Correctness Fixes / BUG-001)
- **Severity:** Medium
- **Symptom:** When a hauler citizen carrying resources died, `CitizenController.die()` released the job without clearing or depositing `carrying_amount` / `carrying_resource`. Subsequently, `WorldView._on_citizen_died()` called `cit.queue_free()`, destroying the carried goods ($\le 10$ units) with the freed node and violating conservation invariant `I-03`.
- **Resolution:**
  - Implemented `CitizenController.recover_cargo(target_rm)` to deposit carried cargo into central storage via `ResourceManager.add_resource()`. If central storage is capped, remaining cargo is safely tracked and logged.
  - In `CitizenController.die()`, `recover_cargo()` is invoked before emitting `citizen_died`.
  - In `WorldView._on_citizen_died()`, a fail-closed safety check calls `cit.recover_cargo(rm)` before node removal using injected `_get_resource_mgr()`.
  - Created automated test suite `scripts/test/test_hauler_death_cargo_conservation.gd` covering 10 scenarios (`TC-CARGO.1` through `TC-CARGO.10`).
- **Verification:** 10/10 automated tests passed (Exit Code 0). Invariant `I-03` promoted to VERIFIED.

### ISSUE-005: Real-Time Tactical Field Combat & Field Siege Operations (Resolved in Packages 1W & 1X)
- **Severity:** Low / Architectural Scope Boundary
- **Symptom:** Tactical unit-on-unit RTS micro combat (stances, manual targeting, enemy field patrol engagements, and field siege operations) was initially deferred during early phases.
- **Resolution:** Implemented `TacticalMilitaryManager` & `TacticalUnit` (Package 1W) and `EnemyMilitaryManager`, `EnemyTacticalUnit`, `FieldSiegeManager`, & `SiegeObjective` (Package 1X), providing full real-time tactical unit control, formations, control groups, enemy AI state machines (`HOLD`, `PATROL`, `ACQUIRE_TARGET`, `PURSUE`, `ATTACK`, `RECOVER_RETREAT`), and field siege campaigns with deterministic save/load persistence.

### ISSUE-004: Live Production Settlement Battle Trigger (Resolved in Package 1K)
- **Severity:** Low / Architecture Scope Boundary
- **Symptom:** `BattleResolver.resolve_settlement_battle` was previously not hooked into the live game loop upon war declaration.
- **Resolution:** Implemented `BattleCampaignManager` (`scripts/combat/battle_campaign_manager.gd`), wiring `FactionManager.war_declared` to schedule incoming settlement raids (3-day initial delay, 5-day recurring interval), querying living guards gated by active Barracks, applying casualties deterministically, plundering resources, and persisting state across saves. Verified with 14 automated tests in `scripts/test/test_live_battle_loop.gd`.

### ISSUE-001: Godot Editor Did Not Auto-Connect MCP Bridge on Direct Executable Launch
- **Severity:** Medium
- **Symptom:** `get_godot_status` reported `connected: false` even though Godot process was running.
- **Root Cause:** Launching `Godot_v4.7-stable_win64.exe` without command-line arguments opens Godot's Project Manager, not the game project. In Project Manager mode, project plugins (including `godot_mcp`) are not loaded.
- **Resolution:** Launch Godot editor targeting the project directory:
  ```powershell
  & "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" -e --path "E:\KINGDOMS UNBOUND\kingdoms-unbound"
  ```
- **Verification:** MCP bridge connected successfully on port 6505, confirmed via `get_godot_status` and `diagnose_connection`.

### ISSUE-002: Corrupt PNG Import Warning on `kingdom_visual_reference.png`
- **Severity:** Low
- **Symptom:** Godot scanner reported `WARNING: Not a PNG file` / `ERR_FILE_CORRUPT` for `res://docs/reference/kingdom_visual_reference.png`.
- **Root Cause:** The reference image was encoded as JPEG (JFIF format `FF D8 FF E0`), but named with a `.png` extension inside the project root, triggering Godot's asset importer.
- **Resolution:** Added `docs/.gdignore` so Godot ignores the documentation folder entirely. Deleted the invalid `kingdom_visual_reference.png.import` artifact.
- **Verification:** Godot headless project scan completed with zero errors and zero warnings.

### ISSUE-003: "No main scene defined in project" Exit Code
- **Severity:** Expected Behavior (Phase 0)
- **Symptom:** Running the project executable directly without a scene argument exits with error "Can't run project: no main scene defined".
- **Status:** Expected during Phase 0 prior to creating `MainMenu.tscn` / `WorldView.tscn` in Phase 1.
- **Resolution:** Main scene will be assigned to `res://scenes/ui/main_menu.tscn` during Phase 1 Task 1.9.
