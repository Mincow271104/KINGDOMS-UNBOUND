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

### ISSUE-010: Dynamic Non-Recurring Jobs Accumulated Unboundedly in JobManager._jobs (Resolved in Batch 2 / BUG-002)
- **Severity:** Medium / Memory & Algorithmic Scalability
- **Symptom:** In `JobManager`, completed (`COMPLETED`) and cancelled (`CANCELLED`) non-recurring jobs (such as hauling batches and temporary construction assignments) remained in the internal `_jobs` registry indefinitely. Over long gameplay sessions with thousands of hauling deliveries or construction tasks, `_jobs` grew monotonically, increasing memory footprint and degrading linear scan performance across `request_job()`, `get_all_jobs()`, and `WorkplaceManager._has_pending_hauling_job()`.
- **Resolution:**
  - Updated `JobManager.complete_job(job)`: When `job.is_recurring` is `false`, sets `job.state = JobState.COMPLETED`, clears `worker_id`, and prunes the job from `_jobs`.
  - Updated `JobManager.cancel_job(job, reason)`: When `job.is_recurring` is `false`, sets `job.state = JobState.CANCELLED`, clears `worker_id`, and prunes the job from `_jobs`.
  - Preserved recurring jobs (`is_recurring = true`): On completion, recurring jobs reset strictly to `JobState.AVAILABLE` with reset work hours and worker IDs, remaining in `_jobs`.
  - Added bounded ring-buffer terminal history: `JobManager._terminal_jobs_history` (bounded at `MAX_TERMINAL_HISTORY = 50`) accessible via `get_recent_terminal_jobs()`, allowing inspection/debugging without unbounded growth.
  - Updated `get_all_jobs()` to return `_jobs.duplicate()`, preventing iterator invalidation when callers iterate and mutate jobs.
  - Authored automated test suite `scripts/test/test_job_lifecycle_pruning.gd` covering 10 scenarios (`TC-JOB.1` through `TC-JOB.10`), including a 1,000-cycle stress test confirming strictly bounded array size.
- **Verification:** 10/10 automated tests passed (Exit Code 0). Invariant `I-05` promoted from PARTIAL to VERIFIED.

### ISSUE-009: Daily Autosave Overwriting Manual Save Slot (Resolved in Batch 2 / BUG-003)
- **Severity:** Medium / Data Integrity & Player Control
- **Symptom:** In `WorldView._on_simulation_day_passed()`, daily autosave invoked `SaveManager.save_to_file("user://saves/world_save.json")`, directly overwriting the player's manual save slot and preventing players from retaining manual checkpoints.
- **Resolution:**
  - Designated `user://saves/autosave.json` (`AUTOSAVE_PATH`) as the dedicated autosave file path in `SaveManager`.
  - Implemented dynamic test redirect `set_test_autosave_path()` and `get_autosave_path()`.
  - Added dedicated API methods `SaveManager.has_autosave()`, `SaveManager.save_autosave()`, and `SaveManager.load_autosave()`.
  - Leveraged `SaveManager.save_dict_to_file()` dynamic path handling to provide independent backup rotation (`.bak`, `.tmp`, `.bak.old`) for autosaves without altering manual save backups.
  - Updated `WorldView._on_simulation_day_passed()` to target `SaveManager.get_autosave_path()`.
  - Added player recovery UI:
    - Pause Menu in HUD (`scripts/ui/hud.gd`): `RestoreAutosaveBtn` (`🔄 Nạp Bản Tự Động Lưu`) allowing the player to reload the latest daily autosave during gameplay.
    - Main Menu (`scripts/ui/main_menu.gd`): `btn_load_autosave` (`🔄 Tải Bản Tự Động Lưu`) dynamically displayed when an autosave exists.
  - Authored automated test suite `scripts/test/test_save_slot_isolation.gd` covering 10 scenarios (`TC-SAVE-ISO.1` through `TC-SAVE-ISO.10`).
- **Verification:** 10/10 automated tests passed (Exit Code 0). Invariant `I-11` promoted to VERIFIED.

### ISSUE-008: HUD Offensive Campaign Outcome Feedback False Success (Resolved in Post-2J Correctness Fixes / RISK-008)
- **Severity:** Low / Presentation Truthfulness
- **Symptom:** `HUD.attack_faction()` evaluated only `res.get("success", false)` (whether the campaign battle executed) and displayed positive feedback (`⚔️ Đã hoàn thành chiến dịch tấn công!`) with a click SFX even when the player's expeditionary force was completely routed (`report.victor == "defender"`).
- **Resolution:**
  - Updated `HUD.attack_faction()` in `scripts/ui/hud.gd` to inspect `report.victor` (supporting both Dictionary and Object-based `BattleReport` representations).
  - Explicitly branched into:
    - `"attacker"`: Green victory banner (`Chiến Thắng!`) and positive click audio.
    - `"defender"`: Red defeat banner (`Thất Bại Chiến Dịch!`) with error audio and error feedback flag.
    - `"draw"` / `"stalemate"`: Neutral stalemate banner (`Bất Phân Thắng Bại`).
    - Failure / Unready: Red failure banner with reason and error audio.
    - Unknown / Corrupted: Fail-closed neutral message, never falsely claiming victory.
  - Created automated test suite `scripts/test/test_campaign_result_feedback.gd` covering 8 scenarios (`TC-FEEDBACK.1` through `TC-FEEDBACK.8`).
- **Verification:** 8/8 automated tests passed (Exit Code 0). Invariant `I-15` promoted to VERIFIED.

### ISSUE-007: Hauler Cargo Destroyed on Citizen Death (Resolved in Post-2J Correctness Fixes / BUG-001)
- **Severity:** Medium
- **Symptom:** When a hauler citizen carrying resources died, `CitizenController.die()` released the job without clearing or depositing `carrying_amount` / `carrying_resource`. Subsequently, `WorldView._on_citizen_died()` called `cit.queue_free()`, destroying the carried goods ($\le 10$ units) with the freed node and violating conservation invariant `I-03`. Furthermore, if central storage was already at capacity upon death, unaccepted cargo remained vulnerable upon citizen node freeing.
- **Resolution:**
  - Implemented `CitizenController.recover_cargo(target_rm)` to deposit carried cargo into central storage via `ResourceManager.add_resource()`.
  - In `WorldView._on_citizen_died()`, any remaining cargo that cannot fit into central storage due to capacity constraints is durably transferred into `WorldView.pending_death_cargo` before the deceased citizen node is freed.
  - Implemented `WorldView.flush_pending_death_cargo()` which automatically flushes pending cargo into central storage whenever space becomes available (hourly simulation, daily rollover, or manual flush).
  - Persisted `pending_death_cargo` in `SaveManager` under `resources` section with full backward compatibility.
  - Clarified standard gameplay pickup capacity (`carry_capacity = 10`), preserving larger test fixtures as boundary/stress verifications.
  - Created automated test suite `scripts/test/test_hauler_death_cargo_conservation.gd` covering 12 scenarios (`TC-CARGO.1` through `TC-CARGO.11`).
- **Verification:** 12/12 automated tests passed (Exit Code 0). Invariant `I-03` promoted to VERIFIED.

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
