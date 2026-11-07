# PACKAGE 2M — CIVIC BUILDING DAMAGE & MAINTENANCE REPAIR
**Authoritative Scope & Technical Implementation Specification**  
**Game Design Document Reference:** `docs/GDD.md` §7.2 (Building Operational Lifecycle, Durability, Damage & Maintenance)  
**Scope Decisions Reference:** `docs/SCOPE_DECISIONS.md` §1.7, §1.8  
**Target Branch:** `feature/package-2m-building-damage-repair`  
**Base Commit:** (Head of `feature/package-2l-citizen-roster`)  
**Known Baseline Failure Addressed:** `TC-ARMY.32` in `scripts/test/test_player_army.gd`

---

## 1. OBJECTIVE & PLAYER EXPERIENCE GAP

### The Problem in Current Gameplay:
In KINGDOMS UNBOUND, civic buildings are currently indestructible structures that remain permanently active once constructed:
1. **No Operational Damage State:** When enemy raids attack or disasters strike, buildings cannot enter a degraded or "damaged" state that halts their utility without outright deleting the building.
2. **Missing Maintenance & Repair Loop:** GDD §7.2 specifies that buildings suffer operational wear and tactical damage, requiring builders to consume materials (Wood, Stone) to restore durability. Currently, no repair jobs exist in `JobManager`.
3. **Known Regression Baseline Failure (`TC-ARMY.32`):** `scripts/test/test_player_army.gd` tests live Barracks operational state transitions:
   - Barracks entering `damaged` state must immediately drop provided military capacity to `0` and disable recruitment in the HUD, while preserving existing soldiers.
   - Restoring Barracks to `active` must restore military capacity and re-enable recruitment.
   Because `WorldView.set_building_state()` does not fully cascade damage deactivation to dependent subsystems (military capacity, workplace operations, housing capacity), `TC-ARMY.32` fails with exit code 1.

### The Package 2M Goal:
Implement the complete **Civic Building Damage & Maintenance Repair** lifecycle conforming strictly to GDD §7.2:
- Introduce explicit building durability (`durability`, `max_durability`), operational status (`active`, `damaged`, `repairing`, `paused`, `under_construction`).
- Cascade damaged state deactivation across all systems: Barracks (capacity = 0, recruit disabled), Workplaces (production halted, workers unassigned), Houses (living capacity suspended), and Storage (dropoff disabled).
- Provide manual and automated Builder repair dispatch with material costs (proportional wood/stone).
- Resolve `TC-ARMY.32` cleanly without altering test assertions, turning the regression runner 63/63 green.

---

## 2. DETAILED EXECUTABLE SCOPE

### 2.1. Building Data Model & State Machine (`scripts/world/world_view.gd`, `scripts/economy/building_system.gd`)
- **Durability Fields in Building Dictionary:**
  ```gdscript
  {
      "id": "barracks_1",
      "type": "barracks",
      "cell": Vector2i(20, 20),
      "level": 1,
      "state": "active",          # "active", "damaged", "repairing", "paused", "under_construction"
      "durability": 100.0,
      "max_durability": 100.0,
      "repair_progress": 0.0,
      "repair_cost": {"wood": 5, "stone": 2}
  }
  ```
- **State Transitions:**
  - `damage_building(building_id, amount)`: Decreases durability. If durability reaches `<= 0.0` or threshold `<= 25%`, state transitions to `"damaged"`.
  - `set_building_state(building_id, new_state)`: Updates state and emits `building_state_changed(building_id, new_state)`.
  - On `"damaged"`:
    - If `type == "barracks"`: Signals `PlayerArmyManager.notify_capacity_changed()`. Army capacity excludes damaged barracks.
    - If workplace: Notifies `WorkplaceManager` to pause production.
    - If house: Evicts or marks living capacity temporarily unavailable.
  - On `"active"`: Restores full operational capacity.

### 2.2. Builder Repair Dispatch & Material Flow
- **Repair Job Type (`job_type = "repair"`):**
  - When a building is damaged, a repair request is registered with `JobManager`.
  - Builders claim the repair job, haul required repair materials from storehouse/townhall, and perform repair labor.
  - Upon completion: `durability` restored to `max_durability`, state restored to `"active"`, and building resumed.
- **Manual Repair Command:**
  - In `CitizenInspectPanel` or `WorldView`, clicking a damaged building allows direct manual builder dispatch ("Sửa chữa công trình").

### 2.3. HUD & UI Integration (`scripts/ui/hud.gd`)
- **Building Inspect Panel:**
  - Shows durability bar (`DurabilityBar`), current health percentage, and repair button if damaged.
- **Army & Recruitment Reflection:**
  - Recruit button disabled when effective capacity is reached or when barracks is damaged.
  - Army count label displays accurate capacity (e.g. `3 / 0 (Doanh trại hỏng)`).
- **Citizen Roster Reflection:**
  - Citizens whose workplace is damaged report appropriate diagnostic in `get_citizen_idle_reason()` ("Nơi làm việc bị hư hại").

### 2.4. Save/Load Persistence (`scripts/persistence/save_manager.gd`)
- Building durability, state, and active repair progress serialize and deserialize cleanly in `world_data.buildings`.
- Backward compatibility: Legacy saves without `durability` default to `100.0` and `"active"`.

---

## 3. IMPLEMENTATION WORKFLOW

1. **Preflight & Branch Setup:**
   - Create and checkout branch `feature/package-2m-building-damage-repair`.
   - Baseline regression check: 62/63 suites pass, 1 baseline fail (`TC-ARMY.32`).
2. **Core Production Implementation:**
   - Implement durability & state cascade in `scripts/world/world_view.gd`.
   - Update `PlayerArmyManager.get_army_capacity()` to filter out damaged barracks (`b.get("state", "active") == "active"`).
   - Ensure `notify_capacity_changed()` updates HUD recruitment button and army labels immediately.
   - Implement repair job lifecycle in `JobManager` and `CitizenController`.
3. **Verification of Baseline Fix:**
   - Run `test_player_army.gd` -> Verify `TC-ARMY.32` passes cleanly with exit code 0.
4. **Authored Dedicated Test Suite (`test_building_damage_repair.gd`):**
   - Author comprehensive unit & integration tests covering damage, deactivation cascade, repair labor, material consumption, and persistence.
5. **Full Regression Run:**
   - Run `run_regression.ps1` -> Verify 63/63 suites pass (100% green, 0 baseline failures, 0 regressions).

---

## 4. DEFINITION OF DONE & ACCEPTANCE CRITERIA

- [ ] `world_instance.call("set_building_state", b_id, "damaged")` cascades capacity drop to 0 in `PlayerArmyManager`.
- [ ] Existing soldiers are strictly preserved when barracks is damaged.
- [ ] Recruit button in HUD is disabled when barracks is damaged.
- [ ] Reactivating barracks restores capacity to full and re-enables recruitment.
- [ ] Demolishing barracks drops capacity to 0 and preserves soldiers.
- [ ] `test_player_army.gd` (TC-ARMY.32) passes with Exit Code 0 (0 failures).
- [ ] Dedicated suite `test_building_damage_repair.gd` passes with Exit Code 0.
- [ ] Full regression suite runs 63 suites with 63 PASS, 0 failures, Exit Code 0.
- [ ] No regression in existing citizen, military, trade, economy, or persistence systems.
- [ ] Working tree clean, changes documented in `docs/WORKLOG.md` and `docs/planning/GAME_COMPLETION_ROADMAP.md`.
