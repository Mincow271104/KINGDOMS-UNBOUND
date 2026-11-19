# KINGDOMS UNBOUND — SESSION 1.3.3
# FINAL PRODUCTION CALL-PATH CLOSURE & INDEPENDENT ACCEPTANCE EVIDENCE REPORT

**Date:** 2026-11-10  
**Engine:** Godot Engine v4.7-stable official (`Godot_v4.7-stable_win64_console.exe`)  
**Repository:** `E:\KINGDOMS UNBOUND\kingdoms-unbound`  
**Current Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Reference Checkpoint HEAD:** `fa09df2fd152a874dbc26461435644ad8822c34e`  
**Report Type:** Production Engineering Handoff & Acceptance Evidence  
**Final Verdict:** `SESSION 1.3.3 VERIFIED — READY FOR INDEPENDENT REVIEW`

---

## 1. BASELINE AND REPOSITORY INTEGRITY

### A. Environment & Checkpoint State
- **Repository Root:** `E:\KINGDOMS UNBOUND\kingdoms-unbound`
- **Active Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Head Commit:** `fa09df2fd152a874dbc26461435644ad8822c34e`
- **Engine Binary:** `E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe`
- **Platform OS:** Windows 10/11 x86_64, PowerShell host

### B. Git Status & Working Tree Analysis
Every pre-existing file, baseline configuration change, untracked visual validation artifact, test suite, and local `.gd.uid` file from Sessions 0 through 1.3.2 has been strictly preserved. Zero commits, pushes, merges, rebases, stashes, or resets were performed during this session.

#### Working Tree Status (`git status --short`)
```text
 M docs/WORKLOG.md
 M project.godot
 M scripts/combat/field_siege_manager.gd
 M scripts/combat/siege_objective_actor.gd
 M scripts/military/player_army_manager.gd
 M scripts/military/tactical_military_manager.gd
 M scripts/test/test_outpost_garrison_reinforcement.gd
 M scripts/world/world_view.gd
?? docs/SESSION_1_3_3_FINAL_PRODUCTION_CALL_PATH_CLOSURE_REPORT.md
?? docs/visual_validation/
?? scratch/
?? scripts/ai/
?? [all local .gd.uid files]
?? scripts/test/test_hardened_outposts_save_roundtrip.gd
?? scripts/test/test_session1_1_targeted_military_corrections.gd
?? scripts/test/test_session1_2_final_military_audit.gd
?? scripts/test/test_session1_3_1_corrective_verification.gd
?? scripts/test/test_session1_3_2_transaction_integrity.gd
?? scripts/test/test_session1_3_military_transaction_closure.gd
?? scripts/test/test_session1_batch1_ids_and_recall.gd
?? scripts/test/test_session1_batch3_eviction_conservation.gd
```

### C. Git Diff Verification
#### 1. Diff Formatting & Whitespace Cleanliness (`git diff --check`)
```text
warning: in the working copy of 'docs/WORKLOG.md', CRLF will be replaced by LF the next time Git touches it
[Exit Code: 0 - Clean: zero trailing whitespace, zero conflict markers, zero indent errors]
```

#### 2. Modified Files Summary (`git diff --stat`)
```text
 docs/WORKLOG.md                                    | 222 ++++++++++
 project.godot                                      |   1 -
 scripts/combat/field_siege_manager.gd              |  40 +-
 scripts/combat/siege_objective_actor.gd            |   8 +
 scripts/military/player_army_manager.gd            | 473 ++++++++++++++++++++-
 scripts/military/tactical_military_manager.gd      | 168 ++++++--
 .../test/test_outpost_garrison_reinforcement.gd    |   4 +-
 scripts/world/world_view.gd                        |  64 ++-
 8 files changed, 932 insertions(+), 48 deletions(-)
```

---

## 2. DETAILED IMPLEMENTATION CHANGES

### A. [`scripts/world/world_view.gd`](file:///e:/KINGDOMS%20UNBOUND/kingdoms-unbound/scripts/world/world_view.gd)
1. **Function:** `demolish_building_project(b_id: String) -> Dictionary` (lines 2453–2495)
   - **Original Defect:** Demolition executed military eviction (`pam.evict_and_cancel_outpost`) before validating whether `BuildingSystem.demolish_building()` could legally succeed (e.g., storage capacity limits or town hall protection). Furthermore, if `BuildingSystem.demolish_building()` subsequently failed, no rollback existed, leaving the building intact on the map while its garrison had already been evicted to base.
   - **Before Behavior:** `pam.evict_and_cancel_outpost(b_id, true, false)` mutated the garrison and reserve immediately. If `BuildingSystem.demolish_building()` failed, the function returned `{"success": false}`, but the garrison had already evacuated to central reserve.
   - **After Behavior:** 
     1. Preflights `BuildingSystem.can_demolish_building()` *before* touching any military state.
     2. Preflights spawn capacity via `tmm_check.can_allocate_spawns()`.
     3. Captures an exact military snapshot via `pam.get_outpost_military_snapshot(b_id)`.
     4. Executes voluntary eviction under Policy A (`pam.evict_and_cancel_outpost(b_id, true, false)`).
     5. Calls `BuildingSystem.demolish_building()`. If demolition fails, rolls back military state atomically via `pam.restore_outpost_military_snapshot(military_snapshot)` and returns failure.
   - **Why Necessary:** Guarantees demolition is an atomic all-or-nothing transaction across economy, world data, and military state.
   - **Side Effects & Compatibility:** 100% backward compatible. Fully preserves cargo refunds, builder job cleanup, and building selection clearing.

2. **Function:** `set_building_state(b_id: String, new_state: String) -> bool` (lines 2262–2276)
   - **Original Defect:** When an outpost was destroyed by combat or crisis, soldiers remained trapped in nonexistent structures unless explicitly evicted.
   - **After Behavior:** Upon transitioning to `"destroyed"`, invokes `pam.evict_and_cancel_outpost(b_id, true, true)` with `allow_casualties_on_congestion = true` (Policy B), ensuring all garrison and in-transit records are cleanly cleared with zero ghost records.

3. **Function:** `_apply_starting_perks_and_modifiers()` (lines 395–405)
   - **Original Defect:** `hardened_outposts` perk called non-existent `player_army_mgr.sync_state_from_tactical()`.
   - **After Behavior:** Correctly calls `tactical_military_mgr.sync_with_player_army()`.

---

### B. [`scripts/military/player_army_manager.gd`](file:///e:/KINGDOMS%20UNBOUND/kingdoms-unbound/scripts/military/player_army_manager.gd)
1. **Function:** `recruit(count: int = 1) -> Dictionary` (lines 476–520)
   - **Original Defect:** Incremented canonical `soldier_count` and committed resource costs before verifying actual tactical unit node instantiation at the base factory boundary. If generic sync failed, `units.size()` became less than `soldier_count`.
   - **Before Behavior:** Cost committed, `soldier_count += count`, followed by non-authoritative `sync_with_player_army()`.
   - **After Behavior:** Implemented two-phase atomic transaction:
     1. `rm.reserve_cost(cost)` (all-or-nothing).
     2. Directly calls `tmm.spawn_units_at_base(count, true, rally_cell)` with `all_or_nothing = true`.
     3. If spawning fails (e.g. factory instantiation failure or cell exhaustion), calls `tmm.despawn_units(spawned_ids)` on any partials, releases reserved resources via `rm.release_cost(cost)`, and returns failure with zero mutations to `soldier_count`.
     4. On spawn success, commits cost via `rm.commit_cost(cost)`, increments `soldier_count += count`, and emits signals.
   - **Why Necessary:** Eliminates race conditions and ensures canonical strategic reserve matches physical tactical units on map at all times.

2. **Function:** `recall_soldier(outpost_id: String, count: int = 1) -> Dictionary` (lines 1535–1570)
   - **Original Defect:** Popped soldiers from `garrisons[outpost_id]["soldiers"]` and incremented `soldier_count` before verifying tactical unit node instantiation.
   - **Before Behavior:** Garrison popped, `soldier_count += count`, then generic sync called.
   - **After Behavior:** Preflights `_get_available_spawn_slots(count)`. Spawns tactical units first via `tmm.spawn_units_at_base(count, true, rally_cell)`. If spawning fails, cleans up partials and aborts with zero mutations to garrison or `soldier_count`. Only on spawn success are soldiers popped from garrison and `soldier_count` incremented.
   - **Why Necessary:** Prevents soldiers from disappearing into limbo or inflating strategic reserve without tactical representation.

3. **Function:** `_get_available_spawn_slots(needed: int) -> int` (lines 1805–1825)
   - **Original Defect:** Contained `if not is_instance_valid(world_view): return needed`, causing standalone instances and unlinked managers to fail open.
   - **After Behavior:** Removed all fail-open fallbacks. When `tactical_military_mgr == null` or `nav == null`, available capacity evaluates strictly to `0`.

4. **Function:** `evict_and_cancel_outpost(outpost_id, retreat_to_central, allow_casualties_on_congestion)` (lines 1826–1954)
   - **Policy A (Voluntary Demolition):** Strict all-or-nothing fail-closed (`allow_casualties = false`). If `available_spawns < total_needed` or factory instantiation fails, returns failure with 0 mutations.
   - **Policy B (Forced Destruction / Hostile Capture):** Evacuates up to available unique walkable spawn capacity (`want_to_spawn := mini(total_needed, available_spawns)`). Remaining soldiers become casualties. Clears all garrison and in-transit records immediately (zero ghost records).

5. **Function:** `advance_reinforcements(delta: float) -> Array` (lines 1665–1725)
   - **Policy C (Arrival at Dead/Captured Outpost):** Evacuates returning soldiers up to available base spawn capacity. Excess soldiers become casualties. Clears in-transit records cleanly.

6. **Functions:** `get_outpost_military_snapshot()` & `restore_outpost_military_snapshot()` (lines 1955–2016)
   - Captures and restores pre-existing unit IDs, positions, states, ID counters (`next_soldier_id`, `next_reinforce_id`), and garrison/reinforcement records.
   - Despawns *only* newly spawned tactical units via `tmm.despawn_units(spawned_unit_ids)` without invoking generic sync.

---

### C. [`scripts/military/tactical_military_manager.gd`](file:///e:/KINGDOMS%20UNBOUND/kingdoms-unbound/scripts/military/tactical_military_manager.gd)
1. **Function:** `sync_with_player_army(prefer_field_casualties, location_restricted) -> Dictionary` (lines 273–311)
   - **Original Defect:** Contained `player_army_mgr.soldier_count = units.size()`, which silently deleted canonical strategic soldiers if tactical spawning was restricted or congested.
   - **Before Behavior:** Overwrote canonical `soldier_count` with tactical roster size upon every sync.
   - **After Behavior:** Removed truncation of `soldier_count`. Returns an explicit `Dictionary`: `{"success": bool, "spawned": int, "needed": int, "reason": String}`.
2. **Function:** `despawn_units(unit_ids: Array) -> void` (lines 260–272)
   - Safely removes and frees specified unit instances by ID, prunes invalid units, and emits `tactical_state_updated`.
3. **Function:** `spawn_units_at_base(count, all_or_nothing, rally_cell) -> Array` (lines 215–259)
   - Instantiates tactical units onto distinct walkable cells around the rally point. If `all_or_nothing` is true and fewer units spawn than requested, cleanly frees all partial spawns and returns an empty array.

---

### D. [`scripts/test/test_session1_2_final_military_audit.gd`](file:///e:/KINGDOMS%20UNBOUND/kingdoms-unbound/scripts/test/test_session1_2_final_military_audit.gd)
1. **Section:** Group C (`TC-1.2.05a..d`, `TC-1.2.06a..h`, lines 169–211)
   - **Original Defect in Test:** The test was originally written in Session 1.2 to demonstrate the architectural bug where soldiers remained trapped inside destroyed buildings. When Session 1.3 mandated Policy B, the test's outdated assertions failed.
   - **After Behavior:** Updated Group C assertions to verify Policy B:
     - `TC-1.2.05a`: Garrison is cleanly cleared to 0 (no soldiers trapped in destroyed building).
     - `TC-1.2.05b`: Reserve remains 7 (0 refunded due to 0 spawn capacity).
     - `TC-1.2.05c`: Living headcount is 7 (3 casualties cleanly accounted; total soldier conservation 7 + 3 = 10 holds).
     - `TC-1.2.05d`: Without retry trigger, garrison remains 0 (zero ghost records).
     - `TC-1.2.06a..f`: Save/load preserves clean post-destruction state (0 garrison, 7 reserve, 7 living).
     - `TC-1.2.06g..h`: Idempotent eviction succeeds cleanly; reserve remains stable at 7 (no phantom increments).

---

### E. [`docs/WORKLOG.md`](file:///e:/KINGDOMS%20UNBOUND/kingdoms-unbound/docs/WORKLOG.md)
- Appended complete Session 1.3.3 entry documenting closure of all Session 1 military production-path defects, test outcomes (1,158 assertions passing), and exact transition readiness for Session 2.

---

## 3. GENERIC SYNCHRONIZATION AND MILITARY CALL-PATH AUDIT

The table below catalogs every production call path that invokes `sync_with_player_army()`.

| Caller Function & File | Inspects Result? | Behavior on Sync Failure | Can Canonical Soldier Count Change? | Can Partial Units Remain? | Invariant Maintained? |
| :--- | :---: | :--- | :---: | :---: | :---: |
| `PAM.set_tactical_military_manager` (`player_army_manager.gd:116`) | No | Logs failure; units remain at current count | No | No (No spawns attempted if equal) | Yes |
| `PAM.recruit` (`player_army_manager.gd:502`) | Yes (pre-spawned) | Spawns via `spawn_units_at_base(all_or_nothing)` *before* sync; sync is no-op | No (Rolls back before mutation) | No (All-or-nothing rollback) | Yes |
| `PAM.remove_casualties` (`player_army_manager.gd:1004`) | No | Reduction pass removes exact candidates; reduction never fails | Yes (Authoritative decrement) | No (Deterministic removal) | Yes |
| `PAM.station_soldier` (`player_army_manager.gd:1515`) | No | Reduction pass prunes exact stationed count from idle base units | Yes (Authoritative decrement) | No (Exact prune) | Yes |
| `PAM.recall_soldier` (`player_army_manager.gd:1548`) | Yes (pre-spawned) | Spawns via `spawn_units_at_base(all_or_nothing)` *before* sync; sync is no-op | No (Fails closed before mutation) | No (All-or-nothing rollback) | Yes |
| `PAM.dispatch_reinforcements` (`player_army_manager.gd:1620`) | No | Reduction pass prunes exact dispatched count from idle base units | Yes (Authoritative decrement) | No (Exact prune) | Yes |
| `PAM.evict_outpost_garrison` (`player_army_manager.gd:1750`) | No | Preflights capacity; only called standalone when retreat enabled | Yes (Incremented on success) | No (Preflight checked) | Yes |
| `PAM.cancel_outpost_reinforcements` (`player_army_manager.gd:1790`) | No | Preflights capacity; only called standalone when retreat enabled | Yes (Incremented on success) | No (Preflight checked) | Yes |
| `TMM.set_player_army_manager` (`tactical_military_manager.gd:89`) | No | Initial binding synchronization | No | No | Yes |
| `TMM.set_rally_cell` (`tactical_military_manager.gd:114`) | No | Repositions or verifies perimeter units | No | No | Yes |
| `TMM.clear_field_combat_state` (`tactical_military_manager.gd:941, 949`) | No | Re-aligns roster if combat reset clears units | No | No | Yes |
| `WorldView._apply_starting_perks_and_modifiers` (`world_view.gd:400`) | No | Initial perk bonus (+2 soldiers); genesis map has ample capacity | Yes (Genesis +2) | No | Yes |
| `SaveManager.apply_loaded_state_to_world` (`save_manager.gd:374`) | No | Reconstructs units for loaded `soldier_count` from validated save | No (Loaded from save) | No (Save validated) | Yes |

### Invariant Preservation Summary
- **Invariant B (`units.size() == soldier_count`)** is maintained as a hard invariant across all transactions.
- Generic synchronization is non-authoritative regarding headcount; only explicit transactions (recruitment, casualties, stationing, recall, eviction) mutate `soldier_count`.
- In all additive operations (`recruit`, `recall`, `evict_and_cancel_outpost`), physical tactical unit instantiation is executed *prior* to canonical state mutation using `all_or_nothing = true`.

---

## 4. RECRUITMENT AND RECALL TRANSACTION DETAILS

### A. Recruitment Call-Path Sequence (`PAM.recruit`)
```mermaid
sequenceDiagram
    autonumber
    actor Player
    participant PAM as PlayerArmyManager
    participant RM as ResourceManager
    participant TMM as TacticalMilitaryManager

    Player->>PAM: recruit(count)
    PAM->>PAM: can_recruit(count) [preflight cost, barracks cap, spawn cells]
    alt Preflight Fails
        PAM-->>Player: return {"success": false, "reason": ...}
    end
    PAM->>RM: reserve_cost(cost) [all-or-nothing]
    alt Reserve Fails
        PAM-->>Player: return {"success": false, "reason": "Cannot reserve"}
    end
    PAM->>TMM: spawn_units_at_base(count, all_or_nothing=true, rally_cell)
    alt Spawning / Instantiation Fails
        TMM->>TMM: despawn_units(partial_spawned_ids)
        PAM->>RM: release_cost(cost) [full reservation refund]
        PAM-->>Player: return {"success": false, "reason": "Spawn instantiation failed"}
    end
    PAM->>RM: commit_cost(cost) [deduct inventory]
    PAM->>PAM: soldier_count += count
    PAM->>TMM: sync_with_player_army() [Already synchronized, returns immediately]
    PAM->>Player: emit recruitment_completed & return {"success": true}
```

### B. Recall Call-Path Sequence (`PAM.recall_soldier`)
```mermaid
sequenceDiagram
    autonumber
    actor Player
    participant PAM as PlayerArmyManager
    participant TMM as TacticalMilitaryManager

    Player->>PAM: recall_soldier(outpost_id, count)
    PAM->>PAM: _get_available_spawn_slots(count)
    alt Available Slots < Count (or TMM/Nav null)
        PAM-->>Player: return {"success": false, "reason": "Insufficient base spawn capacity"}
    end
    PAM->>TMM: spawn_units_at_base(count, all_or_nothing=true, rally_cell)
    alt Spawning / Instantiation Fails
        TMM->>TMM: despawn_units(partial_spawned_ids)
        PAM-->>Player: return {"success": false, "reason": "Spawn instantiation failed"}
    end
    PAM->>PAM: garrisons[outpost_id].soldiers.pop_back() (count times)
    PAM->>PAM: soldier_count += count
    PAM->>TMM: sync_with_player_army() [Already synchronized]
    PAM->>Player: emit garrison_changed, army_changed & return {"success": true}
```

### Proof of Non-Destructive Failure
1. **Failed Recruitment:** If `spawn_units_at_base` fails, `release_cost()` releases the exact reservation in `ResourceManager`. `soldier_count` is never incremented. `units.size()` remains unchanged. Zero gold, food, or metal is lost.
2. **Failed Recall:** If `spawn_units_at_base` fails, `garrisons[outpost_id]["soldiers"]` is never popped. `soldier_count` is never incremented. All soldiers remain safely stationed in the outpost.

---

## 5. DEMOLITION TRANSACTION ATOMICITY

### Sequence in `WorldView.demolish_building_project()`
```mermaid
flowchart TD
    Start([demolish_building_project]) --> CheckExists{Building exists?}
    CheckExists -- No --> RetNotFound[Return failure: Building not found]
    CheckExists -- Yes --> CheckCanDemo{BuildingSystem.can_demolish_building?}
    CheckCanDemo -- No --> RetCannotDemo[Return failure: Storage full / Townhall / Upgrading]
    CheckCanDemo -- Yes --> CheckMilitary{Has Garrison or In-Transit?}
    CheckMilitary -- No --> ExecDemo[BuildingSystem.demolish_building]
    CheckMilitary -- Yes --> CheckSpawnSlots{TMM & Nav have spawn slots?}
    CheckSpawnSlots -- No --> RetCongested[Return failure: Base congested]
    CheckSpawnSlots -- Yes --> TakeSnapshot[Capture Military Snapshot]
    TakeSnapshot --> ExecEvict[pam.evict_and_cancel_outpost Policy A]
    ExecEvict --> CheckEvictOk{Eviction succeeded?}
    CheckEvictOk -- No --> RetEvictFail[Return failure: Eviction failed]
    CheckEvictOk -- Yes --> ExecDemo
    ExecDemo --> CheckDemoOk{Demolition Succeeded?}
    CheckDemoOk -- No --> RollbackMilitary[pam.restore_outpost_military_snapshot]
    RollbackMilitary --> RetDemoFail[Return failure: Demolition failed]
    CheckDemoOk -- Yes --> CleanupWorld[Free node, erase cells, release workers]
    CleanupWorld --> EndSuccess([Return success])
```

### Rollback Verification on Subsequent Failure
If `BuildingSystem.demolish_building()` fails after military eviction:
1. `pam.restore_outpost_military_snapshot(military_snapshot)` is invoked.
2. `tmm.despawn_units(spawned_unit_ids)` despawns *only* the newly spawned tactical units.
3. `soldier_count` is restored to `orig_reserve`.
4. `garrisons[outpost_id]` is fully restored with exact soldier IDs, equipment tiers, and health values.
5. `active_reinforcements` targeting `outpost_id` are restored with original dispatch IDs and timers.
6. Monotonic ID counters (`next_soldier_id`, `next_reinforce_id`) are restored.
7. Pre-existing tactical units on the map are 100% untouched.

---

## 6. SOLDIER CONSERVATION AND TACTICAL EQUALITY

### The Two Fundamental Invariants
$$\text{Total Headcount} = \text{Central Reserve} + \sum \text{Garrisoned} + \sum \text{In-Transit}$$
$$\text{TacticalUnits}.\text{size}() = \text{Central Reserve}$$

### Numerical State Transitions

| Scenario | Initial State (Res / Gar / Tr / Total / Tac) | Operation | Final State (Res / Gar / Tr / Total / Tac) | Invariant A | Invariant B | Headcount Delta |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: |
| **Successful Recruitment** | 10 / 0 / 0 / 10 / 10 | `recruit(2)` | 12 / 0 / 0 / 12 / 12 | ✅ Holds | ✅ Holds | +2 (Recruited) |
| **Failed Recruitment** | 10 / 0 / 0 / 10 / 10 | `recruit(2)` [factory fail] | 10 / 0 / 0 / 10 / 10 | ✅ Holds | ✅ Holds | 0 (Aborted) |
| **Successful Recall** | 7 / 3 / 0 / 10 / 7 | `recall_soldier(2)` | 9 / 1 / 0 / 10 / 9 | ✅ Holds | ✅ Holds | 0 (Internal shift) |
| **Failed Recall** | 7 / 3 / 0 / 10 / 7 | `recall_soldier(2)` [congested] | 7 / 3 / 0 / 10 / 7 | ✅ Holds | ✅ Holds | 0 (Aborted) |
| **Successful Demolition** | 8 / 2 / 0 / 10 / 8 | `demolish_building_project` | 10 / 0 / 0 / 10 / 10 | ✅ Holds | ✅ Holds | 0 (Evacuated) |
| **Failed Demolition** | 8 / 2 / 0 / 10 / 8 | `demolish_building_project` [storage full] | 8 / 2 / 0 / 10 / 8 | ✅ Holds | ✅ Holds | 0 (Rolled back) |
| **Forced Destruction (Casualties)** | 7 / 3 / 0 / 10 / 7 | Outpost destroyed (0 capacity) | 7 / 0 / 0 / 7 / 7 | ✅ Holds | ✅ Holds | -3 (Casualties) |
| **Invalid Reinforcement Arrival** | 8 / 0 / 2 / 10 / 8 | Arrives at destroyed outpost (0 cap) | 8 / 0 / 0 / 8 / 8 | ✅ Holds | ✅ Holds | -2 (Casualties) |

### Legitimate Headcount Mutations
Only three categories of operations legitimately modify total realm headcount:
1. **Recruitment (+N):** Adds new soldiers to the realm with gold, metal, and food expenditure.
2. **Combat Casualties (-N):** Field battle casualties, siege casualties, or outpost defense casualties.
3. **Congested Destruction / Trapped Retreat Casualties (-N):** Under Policy B/C, when an outpost is destroyed or reinforcement target is lost, and base capacity cannot accommodate retreat, trapped soldiers become legitimate casualties.

---

## 7. SESSION 1.2 HISTORICAL TEST RECONCILIATION

In Session 1.2, `test_session1_2_final_military_audit.gd` exhibited 6 test failures in Group C. The table below details why each failure occurred, the old expectation, the new authorized Policy B behavior, and the reconciled assertion.

| Test ID | File & Line | Old Expectation (Session 1.2 Flaw) | Authorized Policy B Behavior | Reconciled Assertion | Outcome |
| :--- | :--- | :--- | :--- | :--- | :---: |
| `TC-1.2.05a` | `test_session1_2.gd:183` | `garrison == 3` (Trapped in destroyed building) | Soldiers cannot remain trapped in deleted structure. 0 capacity $\rightarrow$ 3 casualties, garrison cleared. | `pam.get_garrison_count() == 0` | ✅ PASS |
| `TC-1.2.05c` | `test_session1_2.gd:185` | `total_headcount == 10` (Ignored casualties, assumed trapped alive) | 3 soldiers died as casualties during destroyed retreat. Living headcount is 7. | `pam.get_total_soldier_count() == 7` | ✅ PASS |
| `TC-1.2.05d` | `test_session1_2.gd:191` | `garrison == 3` (Trapped permanently without retry) | Zero ghost records remain for destroyed building. | `pam.get_garrison_count() == 0` | ✅ PASS |
| `TC-1.2.06d` | `test_session1_2.gd:203` | `restored_garrison == 3` (Trapped garrison persisted in save) | Save/load cleanly persists 0 ghost garrisons. | `pam.get_garrison_count() == 0` | ✅ PASS |
| `TC-1.2.06f` | `test_session1_2.gd:205` | `restored_headcount == 10` (Unaccounted casualties loaded) | Restored living headcount is 7 (conservation: 7 living + 3 casualties = 10). | `pam.get_total_soldier_count() == 7` | ✅ PASS |
| `TC-1.2.06h` | `test_session1_2.gd:210` | `reserve == 10` (Manual recovery unearned refund) | Idempotent cleanup of already-evicted building returns 0 refund; reserve remains stable at 7. | `pam.soldier_count == 7` | ✅ PASS |

**Test Integrity Certification:** Updating these assertions did not weaken the test. The old expectations were artifacts of the defective Session 1.2 state where soldiers were trapped in destroyed buildings. The new assertions rigorously verify Policy B compliance, zero ghost records, and complete soldier conservation.

---

## 8. COMPLETE TEST EXECUTION EVIDENCE

### Reconciled Assertion Summary (1,158 Active Assertions Across 11 Suites)

| Suite File | Exact PowerShell Command | Exit Code | Total Assertions | Passed | Failed |
| :--- | :--- | :---: | :---: | :---: | :---: |
| `test_session1_2_final_military_audit.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_session1_2_final_military_audit.gd` | **0** | **52** | 52 | 0 |
| `test_session1_3_2_transaction_integrity.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_session1_3_2_transaction_integrity.gd` | **0** | **92** | 92 | 0 |
| `test_session1_3_1_corrective_verification.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_session1_3_1_corrective_verification.gd` | **0** | **95** | 95 | 0 |
| `test_session1_3_military_transaction_closure.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_session1_3_military_transaction_closure.gd` | **0** | **103** | 103 | 0 |
| `test_session1_1_targeted_military_corrections.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_session1_1_targeted_military_corrections.gd` | **0** | **47** | 47 | 0 |
| `test_session1_batch1_ids_and_recall.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_session1_batch1_ids_and_recall.gd` | **0** | **28** | 28 | 0 |
| `test_session1_batch3_eviction_conservation.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_session1_batch3_eviction_conservation.gd` | **0** | **76** | 76 | 0 |
| `test_hardened_outposts_save_roundtrip.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_hardened_outposts_save_roundtrip.gd` | **0** | **23** | 23 | 0 |
| `test_outpost_garrison_reinforcement.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_outpost_garrison_reinforcement.gd` | **0** | **171** | 171 | 0 |
| `test_player_army.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_player_army.gd` | **0** | **52** | 52 | 0 |
| `test_tactical_military.gd` | `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_tactical_military.gd` | **0** | **419** | 419 | 0 |
| **TOTALS** | **11 Targeted Production Military Suites** | **0** | **1,158** | **1,158** | **0** |

### Headless Compilation Check (`test_all_scripts_load.gd`)
- **Command:** `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --script res://scripts/test/test_all_scripts_load.gd`
- **Exit Code:** **0**
- **Outcome:** **150 / 150 scripts compiled cleanly** with zero syntax errors, type errors, or cyclic preload dependencies.

---

## 9. MASTER BUG LEDGER RECONCILIATION (20 AUTHORITATIVE IDS)

The table below reconciles all 20 original findings from Session 0. No finding has been renamed, renumbered, merged, or substituted.

| Master ID | Subsystem | Severity | Original Finding Definition | Current Reconciled Status | Scheduled Phase |
| :--- | :--- | :---: | :--- | :--- | :---: |
| `MBL-BLD-01` | Buildings / Crisis | P1 | Bandit raid targets Town Hall due to `"town_hall"` vs `"townhall"` string mismatch | OPEN (Scheduled) | Session 3 |
| `MBL-BLD-02` | Buildings / Crisis | P1 | Crisis structural damage bypasses `WorldView.damage_building()` state machine | OPEN (Scheduled) | Session 3 |
| `MBL-BLD-03` | Buildings / Economy| P1 | Building destruction mid-repair leaks reserved repair materials | OPEN (Scheduled) | Session 3 |
| `MBL-BLD-04` | Buildings / Economy| P2 | Mid-repair damage silently overwrites pre-damage state and leaks repair ticket | OPEN (Scheduled) | Session 3 |
| `MBL-BLD-05` | Buildings | P2 | Under-construction damage creates indestructible 0 HP ruins | OPEN (Scheduled) | Session 3 |
| `MBL-MIL-01` | Military / Siege | P1 | Garrison eviction and in-transit reinforcement lifecycle when outposts are demolished, destroyed or captured | **FIXED — PENDING INDEPENDENT VERIFICATION** | Session 1 / 1.3.3 |
| `MBL-MIL-02` | Military / Setup | P2 | `hardened_outposts` starting perk desynchronizes headcount and fails SaveManager validation | **FIXED — PENDING INDEPENDENT VERIFICATION** | Session 1 / 1.3.3 |
| `MBL-MIL-03` | Military / Logic | P2 | Garrison/reinforcement ID collisions after save/load and recall spawn safety | **FIXED — PENDING INDEPENDENT VERIFICATION** | Session 1 / 1.3.3 |
| `MBL-CRS-01` | Crisis | P2 | Double-triggering and timer reset in Plague / Bandit Horde crises | OPEN (Scheduled) | Session 3 |
| `MBL-CRS-02` | Crisis | P2 | Locust Swarm famine multiplier infinite stacking on starvation | OPEN (Scheduled) | Session 3 |
| `MBL-CRS-03` | Crisis | P3 | Winter Freeze health damage desynchronizes worker production efficiency | UNCONFIRMED (Design Clarification Required) | Session 3 |
| `MBL-CRS-04` | Crisis / Siege | P3 | Outpost targeting in crisis events affects destroyed/hostile buildings | **INTENDED BEHAVIOR / CLOSED** | Closed (Session 0.5) |
| `MBL-LEG-01` | Legacy / Economy | P1 | Legacy Fund deposit/withdraw arithmetic desynchronizes vault balance | OPEN (Scheduled) | Session 5 |
| `MBL-LEG-02` | Legacy | P2 | Meta-progression perk cost double deduction on reset | OPEN (Scheduled) | Session 5 |
| `MBL-LEG-03` | Legacy / Saves | P2 | SaveManager cross-slot pollution via unsanitized temp files | **PROVISIONALLY RESOLVED** (Pending targeted test) | Session 5 |
| `MBL-UI-01` | UI / Input | P2 | HUD minimap click during active selection triggers ghost unit orders | OPEN (Scheduled) | Session 4 |
| `MBL-UI-02` | UI / HUD | P3 | Resource HUD tooltip negative value formatting overflow | OPEN (Scheduled) | Session 4 |
| `MBL-SAV-01` | Persistence | P1 | Save file corruption on crash during write phase | OPEN (Scheduled) | Session 3 |
| `MBL-SAV-02` | Persistence | P2 | Missing version migration for pre-release campaign saves | OPEN (Scheduled) | Session 3 |
| `MBL-ECO-01` | Economy | P1 | Building demolition forfeits workplace buffer inventory without refund/warning | **DESIGN GATED** (Awaiting Owner Decision) | Session 2 |

---

## 10. FINAL RISK ASSESSMENT

### A. Confirmed Resolved Defects
- **Fail-open dependency risks eliminated:** Missing `tactical_military_mgr` or `navigation` evaluates strictly to 0 spawn capacity.
- **Generic sync non-destructiveness:** `sync_with_player_army()` never decrements canonical `soldier_count` or prunes pre-existing units upon spawn congestion.
- **Two-phase recruitment and recall:** Spawns units all-or-nothing at factory boundary before committing resources or popping garrisons.
- **Atomic demolition and rollback:** Preflights `can_demolish_building()` before eviction and restores exact snapshot if demolition fails.
- **Zero ghost garrisons or trapped soldiers:** Policy B guarantees all garrison and transit records are erased upon building destruction or hostile conquest.

### B. Remaining Unverified Claims & Non-Goals
- **Independent Verification Gate:** Per project rules, `MBL-MIL-01`, `MBL-MIL-02`, and `MBL-MIL-03` are marked `FIXED — PENDING INDEPENDENT VERIFICATION` until verified by an independent third-party audit.
- **Frontend Multi-Selection & UI Controls:** Multi-unit selection box drag and hotkey grouping frontend UI are scheduled for Session 4 (`MBL-MIL-01` UI aspects, `MBL-UI-01`, `MBL-UI-02`).
- **Full Campaign Regression Scope:** This session verified backend military invariants across 11 targeted test suites. It does NOT claim full T4/T5 live multi-hour gameplay regression.

### C. Known Limitations & Boundary Constraints
- If a custom script bypasses `WorldView.demolish_building_project()` and calls `BuildingSystem.demolish_building()` directly on a military structure without coordinating with `PlayerArmyManager`, `world_view.gd` line 2275 logs an invariant violation error. All standard gameplay routes correctly use `WorldView.demolish_building_project()`.

---

## 11. FINAL VERDICT

```text
SESSION 1.3.3 VERIFIED — READY FOR INDEPENDENT REVIEW
```

**Signed off by:** Antigravity Autonomous Pair Programming Agent  
**Session State:** Clean, stable, zero Git mutations, 1,158 / 1,158 assertions passed (100%), 150 / 150 scripts compiled cleanly. Standing by for project owner authorization to proceed to Session 2.
