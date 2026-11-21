# KINGDOMS UNBOUND — CONTROLLED DEFECT REPAIR PROGRAM
# SESSION 2 REPORT: MILITARY UI & OUTPOST INTERACTION CORRECTION
## MBL-UI-01 and MBL-UI-02

**Date:** 2026-11-10  
**Environment:** Godot Engine v4.7.stable.official.5b4e0cb0f (Windows x86_64 console)  
**Repository:** `E:\KINGDOMS UNBOUND\kingdoms-unbound`  
**Active Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Reference HEAD:** `fa09df2fd152a874dbc26461435644ad8822c34e`  
**Session Focus:** MBL-UI-01 (Territorial Outpost Inspection Footprint & Reinforcement Dispatch) and MBL-UI-02 (ArmyPanel Total Realm Headcount & Upkeep).

---

## 1. EXECUTIVE SUMMARY & ACCEPTANCE VERDICT

During **Session 2**, targeted corrections were implemented for the two designated Master Bug records:

1. **MBL-UI-01 (Part A) — SiegeObjectiveActor 2x2 Click Footprint:**
   - **Root Cause:** In `scripts/world/world_view.gd`, `_find_siege_objective_at_cell(cell)` previously performed a fuzzy Manhattan distance check (`d < 2`), and the selection branch in `_handle_left_click()` tested `if obj_at_cell != null and obj_at_cell.current_cell == cell:`. This required clicking the single top-left origin cell, ignoring the 2x2 bounding box of the objective.
   - **Correction:** Implemented half-open rectangular boundary checking (`_is_cell_in_siege_objective`):
     $$\text{origin.x} \le \text{cell.x} < \text{origin.x} + \text{size.x} \quad \text{and} \quad \text{origin.y} \le \text{cell.y} < \text{origin.y} + \text{size.y}$$
     Dynamic objective size support was added via `obj.get("size")` defaulting to `Vector2i(2, 2)`. Both left-click inspection and right-click combat targeting now recognize all 4 footprint tiles while respecting input priority precedence (citizens on cell take Priority 2 before outpost Priority 2.5).

2. **MBL-UI-01 (Part B) — Reinforcement Dispatch via HUD:**
   - **Root Cause:** In `scripts/ui/hud.gd`, `_on_reinforce_outpost_pressed()` previously called `PlayerArmyManager.station_soldier(inspected_building_id, 1)`, instantly stationing soldiers without physical transit or travel time.
   - **Correction:** Replaced with `PlayerArmyManager.dispatch_reinforcements(inspected_building_id, 1)`. Soldiers are deducted from central reserve atomically, enter in-transit tracking, and only transfer into the outpost garrison upon travel completion.
   - **Signal Ordering Hardening:** Fixed a demonstrated direct dependency in `PlayerArmyManager.advance_reinforcements()` where `reinforcement_arrived` was emitted before updating `active_reinforcements = remaining`, ensuring UI listeners observe accurate post-arrival in-transit counts.

3. **MBL-UI-02 — ArmyPanel Total Realm Headcount & Upkeep:**
   - **Root Cause:** In `scripts/ui/hud.gd`, `_refresh_army_panel()` calculated displayed army headcount and food upkeep using only `get_army_count()` (`soldier_count`), which represents solely the central reserve and excluded stationed garrisons and in-transit reinforcements.
   - **Correction:** `_refresh_army_panel()` now queries the authoritative helper `PlayerArmyManager.get_total_soldier_count()`:
     $$\text{Total Headcount} = \text{soldier\_count (Central Reserve)} + \sum \text{Garrisoned} + \sum \text{In-Transit}$$
     Upkeep display now matches `process_daily_upkeep()`, accurately reflecting total food consumption across the entire realm. Movement order buttons remain guarded by `central_reserve > 0`. Connected HUD listeners to `garrison_changed`, `reinforcement_dispatched`, and `reinforcement_arrived`.

4. **Empirical Verification Results:**
   - Authored dedicated 77-assertion regression test suite: `res://scripts/test/test_session2_military_ui.gd` (**77 / 77 PASSED**, Exit Code 0).
   - Executed the complete 5-suite regression matrix: **867 / 867 assertions and checks PASSED (100% Pass Rate)** with Exit Code 0 across all suites.

**Acceptance Verdict:**  
`SESSION 2 VERIFIED — READY FOR INDEPENDENT REVIEW`

---

## 2. REPOSITORY BASELINE & SAFETY AUDIT

### 2.1 Repository Safety Compliance
- **Root:** `E:/KINGDOMS UNBOUND/kingdoms-unbound`
- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **HEAD:** `fa09df2fd152a874dbc26461435644ad8822c34e`
- **Engine Executable:** `E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe`

Zero Git mutations (`commit`, `push`, `merge`, `rebase`, `reset`, `stash`, `clean`, `checkout`, `branch`) were executed. All baseline modifications and visual assets remain strictly preserved.

### 2.2 Files Modified / Created
| File | Subsystem | Nature of Modification |
|---|---|---|
| `scripts/world/world_view.gd` | World / Input | Added `_is_cell_in_siege_objective()`, updated `_find_siege_objective_at_cell()` to half-open bounding box, updated left-click Priority 2.5 and right-click targeting. |
| `scripts/ui/hud.gd` | UI / HUD | Changed `_on_reinforce_outpost_pressed()` to use `dispatch_reinforcements()`; updated `_refresh_army_panel()` to consume `get_total_soldier_count()` for headcount and upkeep; connected garrison/reinforcement signals. |
| `scripts/military/player_army_manager.gd` | Military Backend | Hardened `advance_reinforcements()` to update `active_reinforcements = remaining` before emitting `reinforcement_arrived` signal. |
| `scripts/test/test_session2_military_ui.gd` | Testing | New 77-assertion test suite covering MBL-UI-01 (A1 footprint & A2 dispatch) and MBL-UI-02 (7-state headcount & upkeep lifecycle). |
| `docs/WORKLOG.md` | Documentation | Updated with Session 2 completion record and updated Master Bug Ledger statuses. |
| `docs/SESSION_2_MILITARY_UI_AND_OUTPOST_INTERACTION_REPORT.md` | Documentation | Authored this comprehensive engineering report. |

---

## 3. MBL-UI-01: OUTPOST FOOTPRINT & REINFORCEMENT DISPATCH

### 3.1 Outpost Footprint Hit-Test (Sub-defect A)
#### Root Cause:
`SiegeObjectiveActor` represents a 2x2 territorial outpost anchored at `current_cell`. When the player clicked anywhere on the outpost diamond, `_handle_left_click` checked `if obj_at_cell != null and obj_at_cell.current_cell == cell:`. This meant clicking `(x+1, y)`, `(x, y+1)`, or `(x+1, y+1)` was rejected and fell through to lower priorities.

#### Corrected Hit-Test Implementation:
```gdscript
func _is_cell_in_siege_objective(obj: Node2D, cell: Vector2i) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var origin: Vector2i = obj.current_cell
	var size: Vector2i = obj.get("size") if (obj.get("size") is Vector2i) else Vector2i(2, 2)
	return cell.x >= origin.x and cell.x < origin.x + size.x and cell.y >= origin.y and cell.y < origin.y + size.y

func _find_siege_objective_at_cell(cell: Vector2i) -> Node2D:
	if field_siege_mgr == null:
		return null
	for o in field_siege_mgr.call("get_all_objectives"):
		if o == null or not is_instance_valid(o) or not o.is_alive:
			continue
		if _is_cell_in_siege_objective(o, cell):
			return o
	return null
```
In `_handle_left_click()`:
```gdscript
	# Priority 2.5: Siege Objective Outpost at clicked cell
	var obj_at_cell = _find_siege_objective_at_cell(cell)
	if obj_at_cell != null and _is_cell_in_siege_objective(obj_at_cell, cell):
		if hud != null and hud.has_method("close_citizen_inspector"):
			hud.close_citizen_inspector()
		var obj_size: Vector2i = obj_at_cell.get("size") if (obj_at_cell.get("size") is Vector2i) else Vector2i(2, 2)
		var outpost_data := {
			"id": obj_at_cell.objective_id,
			"type": "outpost",
			"name": obj_at_cell.objective_name,
			"cell": obj_at_cell.current_cell,
			"size": obj_size,
			"state": "active" if obj_at_cell.is_alive else "destroyed",
			"health": int(obj_at_cell.health),
			"max_health": int(obj_at_cell.max_health),
			"owner": obj_at_cell.owning_faction_id,
			"is_outpost": true,
			"is_under_siege": bool(obj_at_cell.get("is_under_active_siege"))
		}
		select_building(outpost_data)
		return
```

### 3.2 Reinforcement Dispatch Lifecycle (Sub-defect B)
#### Production Call Path:
1. **User Action:** Player clicks `ReinforceBtn` in HUD garrison inspector.
2. **Button Handler:** `HUD._on_reinforce_outpost_pressed()` calls `PlayerArmyManager.dispatch_reinforcements(inspected_building_id, 1)`.
3. **Validation & Deduction:**
   - Verifies player ownership, active status, vacant capacity ($\text{garrison} + \text{in\_transit} < \text{capacity}$), and central reserve ($\text{soldier\_count} \ge 1$).
   - Atomically decrements `soldier_count -= 1`.
   - Creates transit record with calculated travel hours: $\max(1.0, \text{Grid Distance} \times 0.1)$.
   - Appends to `active_reinforcements`.
   - Emits `reinforcement_dispatched` and `army_changed`.
4. **UI Immediate Feedback:**
   - `show_event_banner("Điều Binh Tiếp Viện", "Đã điều động 1 binh sĩ tiếp viện (Dự kiến đến sau %.1f giờ).", true, 2.5)`.
   - Garrison count remains unchanged; in-transit counter displays `Đang tiếp viện: 1 quân`.
   - Reinforce button auto-disables if capacity is reached or central reserve is 0.
5. **Hourly Advance & Arrival:**
   - `advance_reinforcements(delta_hours)` accumulates `elapsed_hours`.
   - When `elapsed_hours >= travel_hours`, soldier transfers to `garrisons[outpost_id]`.
   - `active_reinforcements = remaining` is executed.
   - `reinforcement_arrived.emit(dispatch_id, outpost_id, soldier_count)` fires.
   - HUD banner displays `Viện binh đã đến tiền đồn an toàn!`.
   - Garrison counter increases to reflect the new soldier; in-transit counter hides.

---

## 4. MBL-UI-02: TOTAL REALM HEADCOUNT & ARMYPANEL UPKEEP

### 4.1 Authoritative Accounting Definition
All soldiers in the realm are mutually exclusive and partitioned into three non-overlapping pools:
$$\text{Total Realm Military Headcount} = \text{soldier\_count} + \text{all\_garrisoned} + \text{in\_transit}$$

Where:
- $\text{soldier\_count}$: Central mobile army reserve stationed at or deployed from barracks.
- $\text{all\_garrisoned}$: $\sum_{o \in \text{garrisons}} \text{size}(\text{soldiers}_o)$.
- $\text{in\_transit}$: $\sum_{r \in \text{active\_reinforcements}} \text{soldier\_count}_r$.

### 4.2 HUD ArmyPanel Implementation
```gdscript
	var central_reserve: int = int(player_army_mgr.call("get_army_count"))
	var total_soldiers: int = int(player_army_mgr.call("get_total_soldier_count")) if player_army_mgr.has_method("get_total_soldier_count") else central_reserve
	var cap: int = int(player_army_mgr.call("get_army_capacity"))
	var is_sup: bool = player_army_mgr.get("is_supplied")
	var morale: float = player_army_mgr.call("get_combat_morale")
	var upkeep: int = total_soldiers * EconomyConfig.ARMY_DAILY_FOOD_UPKEEP
...
	if army_count_label:
		army_count_label.text = "⚔️ Quân số chính quy: %d / %d lính" % [total_soldiers, cap]
...
	if upkeep_label:
		upkeep_label.text = "🌾 Chi phí duy trì: %d Lương thực / ngày" % upkeep
```
Field movement controls (`move_army_btn`, `return_home_btn`, `attack_campaign_btn`) remain guarded by `central_reserve > 0` because stationed outpost garrisons cannot march into the field via central army commands.

---

## 5. REGRESSION TEST MATRIX & EVIDENCE

The 5 required test suites were executed headlessly against Godot 4.7. All suites passed 100% with **Exit Code 0** and **0 failures**:

| Suite # | Suite Name | File Path | Assertions / Checks | Status | Exit Code |
|:---:|---|---|:---:|:---:|:---:|
| 1 | Session 2 Military UI Suite | `res://scripts/test/test_session2_military_ui.gd` | **77 / 77** | **PASS** | 0 |
| 2 | Outpost Garrison Reinforcement Core | `res://scripts/test/test_outpost_garrison_reinforcement.gd` | **171 / 171** | **PASS** | 0 |
| 3 | Package 1L Player Army Core | `res://scripts/test/test_player_army.gd` | **47 / 47** | **PASS** | 0 |
| 4 | Package 1W Tactical Military Core | `res://scripts/test/test_tactical_military.gd` | **419 / 419** | **PASS** | 0 |
| 5 | GAP-006 All-Scripts Load & Compile | `res://scripts/test/test_all_scripts_load.gd` | **153 / 153** | **PASS** | 0 |
| **TOTAL** | **5 Full Suites** | — | **867 / 867** | **100% PASS** | **0** |

### 5.1 Test Suite Breakdown (`test_session2_military_ui.gd`)
- **Group A1 (Footprint Hit-Test):** 12 assertions verifying clicks at `(20, 20)`, `(21, 20)`, `(20, 21)`, `(21, 21)` select the outpost; outside clicks North, West, East, South, and Southeast do not select; citizen on cell retains Priority 2 precedence over outpost Priority 2.5.
- **Group A2 (Reinforcement Dispatch):** 20 assertions verifying atomic reserve decrement, in-transit creation without immediate garrison increase, total headcount conservation, arrival synchronization, in-transit clearance, and edge cases (invalid outpost, 0 reserve, full capacity).
- **Group B (ArmyPanel 7 States):** 45 assertions verifying total realm headcount and food upkeep across:
  1. All soldiers in central reserve.
  2. Split between reserve and outpost garrisons.
  3. Travelling as in-transit reinforcements.
  4. Post-reinforcement arrival.
  5. Post-reinforcement cancellation.
  6. Post-soldier recall.
  7. Post-outpost evacuation following demolition/destruction.
  Simulation `process_daily_upkeep(10)` matches ArmyPanel upkeep exactly.

---

## 6. AUTHORITATIVE 20-RECORD MASTER BUG LEDGER

In strict compliance with Session 2 instructions, only `MBL-UI-01` and `MBL-UI-02` have been updated to `Implementation Reported — Pending Independent Verification`. All other 18 IDs, descriptions, and severities remain immutable:

| Master ID | Subsystem | Severity | Authoritative Finding Definition | Mandatory Lifecycle Status | Notes / Authority |
|---|---|---|---|---|---|
| `MBL-BLD-01` | Buildings / Crisis | P1 | Bandit Raid Town Hall targeting: `"town_hall"` vs `"townhall"` and fallback candidate issue. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-BLD-02` | Buildings / Crisis | P1 | Crisis damage bypasses WorldView building lifecycle/state transitions. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-BLD-03` | Buildings / Economy | P1 | Building destruction during repair leaks ResourceManager reservation ticket. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-BLD-04` | Buildings / Economy | P2 | Mid-repair damage is overwritten by repair progress. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-BLD-05` | Buildings / World | P1 | Construction damage corruption and permanently destroyed-building map husks. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-MIL-01` | Military / Persistence | P1 | Demolishing/destroying a garrisoned structure traps soldiers and orphans in-transit reinforcements. | **OPEN** | Session 1 scope; pending independent verification. |
| `MBL-MIL-02` | Military / Persistence | P1 | `hardened_outposts` starting perk corrupts army state and SaveManager validation. | **Implementation Reported** | Awaiting independent verification. |
| `MBL-MIL-03` | Military / Outposts | P2 | Garrison/reinforcement ID collisions after save/load and recall spawn safety. | **Implementation Reported** | Awaiting independent verification. |
| `MBL-CRS-01` | Crisis / Citizens | P1 | Drought working-citizen fatigue uses the wrong citizen state enum. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-CRS-02` | Crisis / Combat | P1 | Bandit Horde army interception immunity and free-kills exploit. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-CRS-03` | Crisis / Victory | P3 | Hourly victory snapshot occurs before crisis resolution; design clarification required. | **Deferred** | Design clarification required; deferred. |
| `MBL-CRS-04` | Crisis / Engine | N/A | `trigger_crisis(..., skip_warning=true)` execution contract; intended behavior/documentation only. | **CLOSED** | Intended behavior; documentation only. |
| `MBL-LEG-01` | Legacy / Trade | P1 | `restless_bandits` is omitted from live caravan route risk evaluation. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-LEG-02` | Legacy / Metaprog | P2 | Treasury settlement ignores live kingdom stability. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-LEG-03` | Legacy / Metaprog | P2 | Settlement multi-file interruption window; addressed by commit `ca61815`. | **Provisionally Resolved** | Pending targeted verification of commit `ca61815`. |
| `MBL-UI-01` | UI / Outposts | P1 | Captured territorial outpost inspection footprint (2x2 SiegeObjectiveActor origin-only click) and instant-teleport reinforcement instead of `dispatch_reinforcements`. | **Implementation Reported — Pending Independent Verification** | Session 2 scope; verified by test suite. |
| `MBL-UI-02` | UI / HUD | P2 | ArmyPanel displays central reserve instead of total realm headcount/upkeep. | **Implementation Reported — Pending Independent Verification** | Session 2 scope; verified by test suite. |
| `MBL-SAV-01` | Persistence | P2 | CrisisManager malformed payload type/schema validation and evaluation order. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-SAV-02` | Persistence | P2 | Empty/legacy `crisis_manager` section wipes metadata world modifiers. | **Confirmed / Triaged** | Baseline finding; scheduled for Session 3+. |
| `MBL-ECO-01` | Economy / Buildings | P2 | Workplace demolition output-buffer disposition; design decision required. | **Gated** | Design decision required; gated for Session 3+. |

---

## 7. REMAINING RISKS & UNVERIFIED CLAIMS

1. **Independent Verification vs. Automated Test Evidence:**
   - All tests were executed headlessly by the automated Godot test runner. While empirical evidence confirms 100% pass rates across all 867 assertions, human playtesting and independent code review remain required to transition statuses to CLOSED.
2. **Session 3 Scope Isolation:**
   - Non-military systems (Buildings, Economy, Citizens, Crisis, Diplomacy) remain locked and untouched.

---

## 8. FINAL STATUS

All Session 2 acceptance criteria are met:
- All four cells of 2x2 `SiegeObjectiveActor` select the outpost.
- Outside cells do not select the outpost.
- Citizen Priority 2 precedence is preserved.
- HUD reinforcement button uses travelling dispatch (`dispatch_reinforcements`).
- ArmyPanel displays total realm headcount and accurate daily upkeep across all 7 operational states.
- 867 / 867 regression tests passed with Exit Code 0.

**Final Status:**  
`SESSION 2 VERIFIED — READY FOR INDEPENDENT REVIEW`
