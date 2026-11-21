# DETAILED BUG FINDINGS — KINGDOMS UNBOUND (REVISED V2)

- **Audit Date:** 2026-11-07
- **Committed Baseline HEAD:** `4a99322a6d2efb6bc269914f68d2968734d4b678` (`fix(package-2j): complete warning cleanup and closure verification`)
- **Methodology:** Static source code analysis, call-graph tracing, and reconciliation with test suites.
- **Coverage Disclosure:** Roughly 15–20% of the production GDScript codebase was inspected in full (economy core, workplace/job logistics, citizen cargo/death lifecycle, `WorldView` composition and tick handlers, `SaveManager` load/rollback path, `FieldSiegeManager`, `BattleCampaignManager` raid/offensive loops, `PlayerArmyManager` recruitment and equipment tier authority, `FactionManager` diplomacy APIs, HUD campaign/siege feedback handlers).

---

## 1. Confirmed Bugs

### BUG-001 — Hauler cargo is destroyed when a citizen dies
- **Category:** Economy / Citizen Lifecycle — Silent Resource Destruction
- **Severity:** Medium (bounded: $\le \text{carry\_capacity} = 10$ units per citizen death)
- **Confidence:** **Confirmed (Static)**
- **Status:** **Open**
- **Files & Locations:**
  - `scripts/entities/citizen_controller.gd`: L55–59 (cargo fields `carrying_resource`, `carrying_amount`, `carrying_source_workplace_id`; `carry_capacity = 10`), L372–395 (pickup removes goods from workplace buffer), L769–799 (`die()` releases `active_job`, sets `_death_processed = true`, but never touches or refunds `carrying_*`).
  - `scripts/world/world_view.gd`: L570–605 (`_on_citizen_died()` removes the citizen from lists and calls `cit.queue_free()`; carried cargo is neither refunded to the source workplace buffer nor deposited into `ResourceManager`).
- **Call Chain:**
  Hunger/Health depletion $\rightarrow$ `CitizenController.die()` $\rightarrow$ emits `citizen_died` $\rightarrow$ `WorldView._on_citizen_died()` $\rightarrow$ `citizen_list.erase(cit)` $\rightarrow$ `cit.queue_free()`.
- **Observed Behavior:**
  Goods already removed from `WorkplaceManager` buffer via `pickup_from_buffer()` reside strictly in the citizen node's variables. When the citizen dies, the node is freed, and the goods vanish permanently without trace.
- **Expected Behavior:**
  Economy invariant I-03 ("No silent resource loss"): Cargo should be returned to the source workplace output buffer (clamped to buffer capacity) or deposited into `ResourceManager` central storage, with any over-capacity excess logged as an explicit spill event.
- **Impact Analysis:**
  While bounded to 10 units per event, deaths cluster heavily during starvation crises. When a starving hauler carrying food dies en route, that food is destroyed at the exact moment the settlement needs it most. Furthermore, `SaveManager` (L1947–1949) restores `carrying_*` fields only for living citizens; deceased haulers lose cargo permanently across sessions.
- **Proposed Minimal Safe Fix:**
  In `WorldView._on_citizen_died()` (or within `CitizenController.die()` prior to signal emission):
  ```gdscript
  var c_amt: int = int(cit.get("carrying_amount"))
  var c_res: String = String(cit.get("carrying_resource"))
  var c_src: String = String(cit.get("carrying_source_workplace_id"))
  if c_amt > 0 and not c_res.is_empty():
      var wp_mgr = get_workplace_manager()
      var refunded: int = 0
      if wp_mgr != null and not c_src.is_empty():
          refunded = wp_mgr.refund_cargo_to_buffer(c_src, c_res, c_amt)
      var remainder: int = c_amt - refunded
      if remainder > 0:
          var rm = get_resource_manager()
          if rm != null:
              rm.add_resource(c_res, remainder)
  ```
- **Proposed Regression Tests:**
  1. Citizen dies carrying cargo, source buffer has room $\rightarrow$ buffer restored.
  2. Buffer full, central storage has room $\rightarrow$ `ResourceManager` stock credited.
  3. Conservation assertion: $(\text{stock} + \text{buffer} + \text{carried})$ before death equals $(\text{stock} + \text{buffer})$ after death.

---

## 2. Probable Bugs

### BUG-002 — Dynamic non-recurring jobs are never pruned from `JobManager._jobs`
- **Category:** Citizen/Workplace Simulation — Unbounded Memory Growth & Scan Overhead
- **Severity:** Medium
- **Confidence:** **Probable** (Growth is statically certain; framerate cost has not been profiled)
- **Status:** **Open**
- **Files & Locations:**
  - `scripts/jobs/job_manager.gd`: L208–230 (`request_job()` iterates entire `_jobs` array), L306–316 (`complete_job()` sets non-recurring jobs to `JobState.COMPLETED`), L324–328 (`cancel_job()` sets `JobState.CANCELLED`), L275–280 (`remove_job()` exists but has no production caller).
  - `scripts/economy/workplace_manager.gd`: L287–292 (`_has_pending_hauling_job()` iterates all jobs in `_jobs` hourly per active workplace via `world_view.gd` L2388–2389).
- **Evidence:**
  `remove_job()` is called only during construction building demolition/cleanup. Completed hauling jobs (`create_hauling_job()` creates non-recurring jobs whenever workplace buffer $\ge 5$) stay in `_jobs` indefinitely with state `COMPLETED`.
- **Impact Analysis:**
  In long-running sessions (the core use case for Kingdoms Unbound), `_jobs` grows monotonically. Hourly logistics scans and citizen job-request scans degrade linearly $O(N)$. Note that save/load masks this growth because jobs are not serialized (`sync_workplaces_after_load()` calls `clear_dynamic_jobs()`).
- **Proposed Minimal Safe Fix:**
  Add a pruning pass to `JobManager` (e.g., at the end of `update_hauling_jobs()` or periodically on day rollover) that purges `COMPLETED` and `CANCELLED` non-recurring jobs while strictly preserving recurring starter jobs (`is_recurring == true`) and `RESERVED`/`IN_PROGRESS` jobs.
- **Proposed Regression Tests:**
  Simulate 100 hauling cycles $\rightarrow$ assert `job_mgr.get_all_jobs().size()` remains strictly bounded.

### BUG-003 — Daily autosave overwrites the manual-save slot
- **Category:** Persistence / Data Safety — Loss of Player Save State
- **Severity:** Medium
- **Confidence:** **Probable (Product Intent Question)**
- **Status:** **Open**
- **Files & Locations:**
  - `scripts/world/world_view.gd`: L59–60 (`autosave_enabled = true`, `autosave_interval_days = 1`), L2474–2478 (`SaveManager.save_to_file(self)` called every day rollover without arguments).
  - `scripts/persistence/save_manager.gd`: L8 (`DEFAULT_SAVE_PATH = "user://saves/world_save.json"`), L349–385 (`save_dict_to_file()` rotates `.bak` for the immediately preceding save only).
  - `scripts/ui/hud.gd`: L1999, L2019 (manual save and load dialogs use `DEFAULT_SAVE_PATH`).
  - `scripts/ui/main_menu.gd`: L155 (main menu "Continue" loads `DEFAULT_SAVE_PATH`).
- **Observed Behavior:**
  When a player manually saves their game to `world_save.json`, the very next in-game day (1 real-time minute at normal speed) triggers an automatic save to the exact same file path. If a player manual-saved before launching a risky offensive campaign and fails catastrophically, the subsequent daily autosave overwrites their manual save slot with the post-defeat state.
- **Expected Behavior:**
  GDD Section 8 specifies: "autosave định kỳ tùy cấu hình". Best practices require autosave to target a dedicated slot (e.g., `user://saves/autosave.json`) or maintain numbered slots, preserving the player's explicit manual checkpoint.
- **Proposed Minimal Safe Fix:**
  Introduce a dedicated autosave path constant: `const AUTOSAVE_PATH: String = "user://saves/autosave.json"`. Direct `WorldView._on_simulation_day_passed()` to write to `AUTOSAVE_PATH`. Update the Main Menu / HUD to distinguish "Tiếp tục (Autosave)" from "Tải bản lưu thủ công".

---

## 3. Architectural Risks

### RISK-001 — `ResourceManager.commit_cost()` trusts caller and silently clamps
- **Severity:** Low | **Confidence:** Probable (Latent API Hazard) | **Status:** **Open (Latent)**
- **File:** `scripts/economy/resource_manager.gd` L131–137.
- **Evidence:** `commit_cost()` does not verify whether a prior matching reservation existed. It clamps both `_reserved_stock` and `_current_stock` to `maxi(0, ...)` upon deduction. If an unreserved or over-allocated commit occurs, it silently swallows the error rather than failing. All current production callers (`WorkplaceManager.produce_to_buffer`, `PlayerArmyManager._execute_upgrade_transaction`, `BattleCampaignManager` plunder) reserve immediately before committing synchronously, so no live defect exists today.

### RISK-002 — Resolved siege records accumulate and are re-evaluated each frame
- **Severity:** Low | **Confidence:** Confirmed (Static) | **Status:** **Open**
- **Files:** `scripts/combat/field_siege_manager.gd` L399–408, L507–508, L572; `scripts/world/world_view.gd` L833–839.
- **Evidence:** When a field siege finishes (`VICTORY`, `DEFEAT`, `WITHDRAWAL`), `_resolve_siege_outcome()` sets `active_sieges[sid]["status"] = "resolved"`, but the record is never erased from `active_sieges`. In `WorldView._process()`, the engine iterates all keys in `active_sieges` each frame (early-returning when status is not `"active"`). Furthermore, `serialize()` saves all historical sieges into `world_save.json`.

### RISK-003 — `TacticalUnit.faction_id` defaults to `"player"`
- **Severity:** Low | **Confidence:** Probable (Latent Hazard) | **Status:** **Open (Latent)**
- **Files:** `scripts/military/tactical_unit.gd` L34, L102–111; `scripts/military/enemy_tactical_unit.gd` L31–35.
- **Evidence:** `TacticalUnit.get_equipment_multiplier()` returns 1.0 if `faction_id != "player"`, otherwise it applies the player's equipment multiplier. Base class `TacticalUnit` defaults `faction_id = "player"`. `EnemyTacticalUnit` overrides this in `_ready()`, so NPC units behave correctly today. However, if a future developer creates a new tactical unit subclass and forgets to override `faction_id`, the enemy unit will silently receive player equipment combat buffs.

### RISK-004 — Faction `in_exile` and `eliminated` existence statuses are unreachable
- **Severity:** Low (Design/Feature Gap) | **Confidence:** Confirmed (Static) | **Status:** **Open (Product Question)**
- **Files:** `scripts/factions/faction_data.gd` L180; `scripts/factions/faction_manager.gd` L446–452, L1212.
- **Evidence:** `FactionData.set_existence_status()` has no callers in production gameplay code. Outpost conquest transfers ownership via `transfer_outpost_ownership()`, but never eliminates or exiles the owning faction. Extensive guards and test cases exist for states that natural gameplay cannot enter.

### RISK-005 — Load path frees old citizens via `queue_free()` without `remove_child()`
- **Severity:** Low | **Confidence:** Unverified | **Status:** **Open (Unverified)**
- **Files:** `scripts/persistence/save_manager.gd` L1901–1913 vs building loop L1836–1839.
- **Evidence:** When restoring buildings, `SaveManager` calls `remove_child(child)` before `child.queue_free()`. When restoring citizens, it calls `child.queue_free()` without `remove_child()`. Newly instantiated citizens reuse IDs (`name = cid`), meaning old and new nodes with identical names coexist in the scene tree until the end of the frame. Because lookups use the dictionary index `citizens_by_id` rather than node paths, no live bug has been observed.

### RISK-006 — Documentation drift from working tree
- **Severity:** Medium for Agent Continuity | **Confidence:** Confirmed | **Status:** **CLOSED (RESOLVED in Commit `4a99322`)**
- **Resolution:** In Package 2J closure commit `4a99322`, `docs/KNOWN_ISSUES.md` (`ISSUE-006`) was updated to document `world_view.gd` failure handling and variable shadowing fixes, and `docs/WORKLOG.md` received its closure log entry.

### RISK-007 — Over-capacity stock after storage demolition
- **Severity:** Low (Design Intent) | **Confidence:** Probable | **Status:** **Open (Design Intent)**
- **Files:** `scripts/economy/resource_manager.gd` L284–290; `scripts/economy/building_system.gd` L458–473.
- **Evidence:** When a storage building is demolished, `remove_storage_capacity()` reduces capacity, but deliberately leaves existing stock untouched, allowing current stock to exceed new capacity. `can_demolish_building()` verifies space only for refund materials, not existing excess goods.

### RISK-008 — HUD offensive-campaign feedback reports completion regardless of battle outcome
- **Severity:** Low / Medium (Player Experience & UX Feedback)
- **Confidence:** **Confirmed (Static)**
- **Status:** **Open**
- **Committed Baseline Evidence:**
  - `HEAD:scripts/ui/hud.gd` L1167–1186 (`attack_faction()`):
    ```gdscript
    func attack_faction(faction_id: String) -> Dictionary:
        ...
        var res: Dictionary = battle_campaign_mgr.call("launch_offensive_campaign", faction_id)
        if not res.get("success", false):
            var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
            if am and am.has_method("play_error"): am.play_error()
            show_event_banner("Không Thể Tấn Công", res.get("reason", "Chiến dịch thất bại."), false, 4.0)
            _show_diplomacy_feedback("❌ %s" % res.get("reason", "Không thể tấn công."), true)
        else:
            var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
            if am and am.has_method("play_click"): am.play_click()
            _show_diplomacy_feedback("⚔️ Đã hoàn thành chiến dịch tấn công!", false)
        _refresh_diplomacy_ui()
        _refresh_army_panel()
        return res
    ```
  - `HEAD:scripts/combat/battle_campaign_manager.gd` L805–809 (`launch_offensive_campaign()`):
    ```gdscript
    return {
        "success": true,
        "report": report,
        "context": context
    }
    ```
- **Analysis & Verification:**
  1. `res["success"]` indicates that the campaign simulation executed and resolved without preflight errors (troops were deployed, casualties calculated, diplomacy adjusted).
  2. The actual military outcome resides in `report.victor` (`"attacker"`, `"defender"`, `"draw"`).
  3. When the player attacks and loses their entire field army (`report.victor == "defender"`), `res["success"]` is still `true`.
  4. The HUD evaluates only `res.get("success", false)`, completely ignoring `report.victor`. As a result, it plays a positive click sound (`play_click()`) and prints in green/white text: `⚔️ Đã hoàn thành chiến dịch tấn công!`, failing to inform the player that their forces were wiped out.
  5. *Note on working-tree line numbers:* In the uncommitted working tree, lines shift by +18 due to the experimental AI M2-B toggle button (`_toggle_ai_panel()`), but the underlying code logic is 100% identical to committed HEAD.

---

## 4. Previously Fixed Issues & Regression Test Coverage

| ID | Issue Description | Fix Location | Regression Test Status |
|:---|:---|:---|:---|
| **FIXED-001** | `world_view.gd` attack-order failure banner | `scripts/world/world_view.gd` L1097–1103 | **COVERED:** Tracked suite `scripts/test/test_world_view_siege_input.gd` committed in `4a99322` (30/30 checks PASS). |
| **FIXED-002** | Test parse errors from `const` shadowing ClassDB | `test_factions_and_battles.gd`, `test_faction_diplomacy_ai.gd` | **COVERED:** Suites execute clean (Exit Code 0). Tracked all-scripts parse check remains open (`GAP-006`). |
| **FIXED-003** | Variable shadowing across 14 production files | Production scripts | **COVERED:** Verified via GDScript warning cleanup and 23/24 passing suites. |

---

## 5. Baseline Failure (Known Pre-Existing Limitation)

- **Identifier:** `BASELINE-001` (`TC-ARMY.32`)
- **Suite:** `scripts/test/test_player_army.gd`
- **Observed Result:** `[FAIL] TC-ARMY.32: Damaged barracks still provides capacity: 5` (Exit Code 1).
- **Root Cause:** In Package 2F (commit `a55021c`), `WorldView.set_building_state()` was restricted to operational transitions (`"active"` and `"paused"`), rejecting unsupported states such as `"damaged"`. `test_player_army.gd` was written prior to Package 2F and attempts `set_building_state(b_id, "damaged")`.
- **Classification:** Documented baseline issue (`docs/KNOWN_ISSUES.md` `ISSUE-006`). Not a Package 2J regression.

---

## 6. Disproved / Downgraded Suspicions

- *Equipment multiplier leaks to enemy units:* Disproved. `TacticalUnit.get_equipment_multiplier()` explicitly gates on `faction_id == "player"`, and `EnemyTacticalUnit` sets its own faction.
- *Storage capacity double-applied on save load:* Disproved. `apply_loaded_state_to_world()` restores `_capacities` directly; `apply_completion_effects()` executes only on construction completion.
- *Demolishing under-construction storehouse underflows capacity:* Disproved. `can_demolish_building()` explicitly blocks buildings under construction.
- *AI diplomacy bypasses peace/war signals:* Disproved. `FactionManager` routes AI actions through `declare_war()` and `propose_treaty("peace")`, properly firing signals consumed by `WorldView` and `BattleCampaignManager`.
- *Equipment upgrade double-spend via re-entrancy:* Disproved. Guarded synchronously by `_is_upgrading_equipment` in `PlayerArmyManager`.
- *Stale jobs survive save load:* Disproved. `sync_workplaces_after_load()` calls `clear_dynamic_jobs()`, purging dynamic jobs on load.
