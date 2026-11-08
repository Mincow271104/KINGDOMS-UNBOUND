# KINGDOMS UNBOUND — Known Issues & Technical Resolutions

## Active Issues

*(None — All tracked defects and pre-existing baseline limitations have been resolved as of Package 2M)*

---

## Resolved Issues

### ISSUE-006: Pre-Existing test_player_army.gd TC-ARMY.32 Barracks State Transition & Capacity Gating (Resolved in Package 2M)
- **Severity:** Low / Baseline Test Limitation (BASELINE-001)
- **Symptom:** `scripts/test/test_player_army.gd` test case `TC-ARMY.32` failed with assertion error when testing barracks damage state transitions (`set_building_state(b_id, "damaged")`).
- **Root Cause:** Package 2F (commit `a55021c`) restricted `WorldView.set_building_state()` to valid operational transitions (`"paused"` and `"active"`). `TC-ARMY.32` was written prior to Package 2F and called `set_building_state(b_id, "damaged")`, which was rejected by `WorldView`, leaving capacity at 5 instead of dropping to 0.
- **Resolution (Package 2M):**
  - Authoritative GDD §7.2 building state transitions implemented in `BuildingSystem` and `WorldView`: `"active"`, `"under_construction"`, `"paused"`, `"damaged"`, and `"destroyed"`.
  - When a Barracks is transitioned to `"damaged"`, `PlayerArmyManager.notify_capacity_changed()` dynamically re-evaluates active barracks, dropping granted soldier capacity to 0 while strictly preserving existing living soldiers (zero silent deletion).
  - When repaired back to `"active"`, Barracks capacity is restored to 5 and recruitment re-enables.
  - Implemented complete maintenance and repair lifecycle (`start_repair_building()`, `advance_repair_work()`, `complete_repair()`, `cancel_repair_building()`) with proportional resource reservations via `ResourceManager.reserve_cost()`, `commit_cost()`, and `release_cost()`.
  - Authored dedicated 25-scenario test suite `scripts/test/test_building_damage_repair.gd` (118/118 assertions passing).
- **Verification:** `test_player_army.gd` (TC-ARMY.32) and all 64 regression suites PASS cleanly with Exit Code 0 (0 baseline failures, 0 unexpected regressions).

### ISSUE-014: Absence of Direct Manual Dispatch for Civilian Citizens (Resolved in Package 2K)
- **Severity:** Medium / Core Player Agency (GDD §8.2, §8.3)
- **Symptom:** In the colony simulation, citizens were strictly autonomous and picked up tasks exclusively via `JobManager` according to vocational roles. Left-clicking a citizen opened the inspector, but right-clicking on any world tile (walkable ground, trees, rocks, construction sites, workplace buffers, POIs) did nothing, preventing the player from directly prioritizing urgent tasks or guiding citizen labor.
- **Resolution:**
  - Implemented manual command state machine and public API in `scripts/entities/citizen_controller.gd`: `issue_manual_command()`, `cancel_manual_command()`, `has_manual_command()`, `get_manual_command()`.
  - Added Priority Hierarchy (GDD §8.3): Priority 1 (Emergency safety) > Priority 2 (Vital survival: hunger >= 85 or fatigue >= 90 pauses manual work, resuming automatically once satisfied) > Priority 3 (Manual command overrides routine jobs) > Priority 4-6 (Routine jobs).
  - Cleanly released active routine jobs via `JobManager.release_job(active_job)` upon manual order acceptance, preventing orphaned locks.
  - Implemented strict physical hauling and cargo conservation: citizens harvesting or hauling cargo carry goods physically to the Storehouse/Town Hall before depositing to central inventory (zero teleportation).
  - Integrated right-click targeting resolution and fail-closed validation in `scripts/world/world_view.gd` for Move, Chop, Mine, Build, Haul, and Explore commands, with localized red error banners (`"Lệnh Thất Bại"`) upon invalid targets.
  - Added manual order status, progress, and `"Hủy Lệnh"` cancellation button to `CitizenInspectPanel` in `scenes/ui/hud.tscn` / `scripts/ui/hud.gd`.
  - Updated In-Game Field Guide (`scripts/ui/player_field_guide.gd`) Chapter B with Section 6.
  - Added save/load serialization, deserialization, and schema validation in `scripts/persistence/save_manager.gd` with 100% backward compatibility for legacy saves.
  - Authored automated test suite `scripts/test/test_manual_citizen_commands.gd` covering 15 scenarios (97 assertions).
- **Verification:** 97/97 automated checks PASS (Exit Code 0).

### ISSUE-013: Immediate Save Reload Caused Citizen Node Name Collisions via queue_free() Deferral (Resolved in Batch 3 / RISK-005)
- **Severity:** Low / Scene Tree Architecture
- **Symptom:** In `SaveManager.apply_loaded_state_to_world()`, existing citizens were freed by invoking `child.queue_free()` without first invoking `citizens_container.remove_child(child)`. Because `queue_free()` defers destruction until end-of-frame, the old nodes remained registered in `citizens_container` when newly reconstructed citizens were added (`citizens_container.add_child(cit)` with `cit.name = cid`). Godot detected duplicate child names in the container and automatically renamed new citizens to anonymous IDs (e.g. `@Node2D@4438`), breaking direct node path resolution (`citizens_container.get_node_or_null(cid)`).
- **Resolution:**
  - In `scripts/persistence/save_manager.gd` (line 1955), explicitly invoked `citizens_container.remove_child(child)` before `child.queue_free()`, mirroring the established pattern for `buildings_container`.
  - Authored automated regression suite `scripts/test/test_repeated_save_load_scene_cleanup.gd` verifying 10 scenarios: initial node naming, immediate reload with zero collisions, exact child counts, clean signal wiring, direct node lookups, 5 consecutive rapid reloads, manual vs autosave reloads, valid manager references, and legacy save compatibility.
- **Verification:** 38/38 automated assertions passed (Exit Code 0).

### ISSUE-012: Resolved Field Siege Records Accumulated in active_sieges (Resolved in Batch 3 / RISK-002)
- **Severity:** Low / Memory & Simulation Scalability
- **Symptom:** When a field siege concluded (`VICTORY`, `DEFEAT`, `WITHDRAWAL`), `FieldSiegeManager._resolve_siege_outcome()` marked the siege record as `"resolved"`, but never removed it from `active_sieges`. In `WorldView._process()`, the engine iterated all keys in `active_sieges` each frame, performing redundant status evaluations on historical sieges. Furthermore, `serialize()` wrote all historical sieges into `active_sieges` in save files.
- **Resolution:**
  - Separated active siege tracking from resolved history in `scripts/combat/field_siege_manager.gd`:
    - `active_sieges: Dictionary`: Contains strictly sieges with `status == "active"`.
    - `resolved_sieges_history: Array[Dictionary]`: Bounded FIFO ring buffer holding resolved siege records (`MAX_RESOLVED_HISTORY = 50`).
  - Updated `_resolve_siege_outcome()`: Upon resolution, removes the siege record from `active_sieges` and records it into `resolved_sieges_history`.
  - Maintained idempotent queries: `evaluate_siege_status()`, `get_siege_record()`, and `get_resolved_siege_record()` query both active and historical records seamlessly.
  - Added public history accessors: `get_recent_resolved_sieges()`, `get_resolved_siege_count()`, `get_active_siege_count()`.
  - Hardened `SaveManager`: Added validation for optional `resolved_sieges_history` Array in `field_siege`.
  - Implemented migration normalization in `FieldSiegeManager.deserialize()`: Older saves containing resolved or cancelled records inside `active_sieges` automatically migrate those records to `resolved_sieges_history`, keeping `active_sieges` strictly active.
  - Authored automated test suite `scripts/test/test_siege_record_lifecycle.gd` covering 10 scenarios (51 checks).
- **Verification:** 51/51 automated assertions passed (Exit Code 0).

### ISSUE-011: ResourceManager commit_cost() Lacked Reservation Validation (Resolved in Batch 3 / RISK-001)
- **Severity:** Low / Latent API Hazard
- **Symptom:** `ResourceManager.commit_cost()` and `release_cost()` previously trusted callers without verifying whether a matching reservation existed in the ledger. Unreserved commits silently deducted stock or clamped to 0 (`maxi(0, ...)`), double commits deducted stock twice or clamped to 0, and unreserved releases could steal reservations made by concurrent orders.
- **Resolution:**
  - Implemented strict active reservation tracking in `ResourceManager` using both aggregated dictionaries (`_direct_reservations`) and atomic reservation records (`_direct_reservation_records`).
  - Updated `reserve_cost(cost)` to validate positive integer quantities, reject empty costs, verify affordability, and store an immutable reservation record.
  - Hardened `commit_cost(cost)` to fail closed without state mutations if no matching reservation record exists or if available stock is insufficient, returning a boolean status.
  - Hardened `release_cost(cost)` to fail closed without state mutations if no matching reservation record exists, preventing stolen reservations across concurrent orders.
  - Implemented a formal transaction ticket API: `begin_transaction(cost) -> String`, `commit_transaction(tx_id) -> bool`, `rollback_transaction(tx_id) -> bool`, and `has_active_transaction(tx_id) -> bool` with isolated `_ticketed_reservations`.
  - Authored automated test suite `scripts/test/test_resource_transaction_integrity.gd` covering 11 scenarios (88 checks), verifying direct and ticketed commit/rollback atomicity, fail-closed boundaries, ledger invariance, and end-to-end integration with `BuildingSystem`, `PlayerArmyManager`, and `WorkplaceManager`.
- **Verification:** 88/88 automated assertions passed (Exit Code 0). Invariant `I-02` promoted to VERIFIED.

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
