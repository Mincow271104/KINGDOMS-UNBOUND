# PACKAGE 2K — MANUAL CITIZEN COMMANDS & DIRECT LABOR DISPATCH
**Authoritative Scope & Technical Implementation Specification**  
**Game Design Document Reference:** `docs/GDD.md` §8.2, §8.3 (Direct Commands & Priority Hierarchy)  
**Scope Decisions Reference:** `docs/SCOPE_DECISIONS.md` §1.7, §1.8  
**Target Branch:** `feature/package-2k-manual-citizen-commands`  
**Base Commit:** `ad5c9e5` (`feature/core-systems-hardening`)  

---

## 1. OBJECTIVE & PLAYER EXPERIENCE GAP

### The Problem in Current Gameplay:
In the current game, citizens are 100% autonomous; they pick up jobs exclusively from `JobManager` according to their assigned vocational role. While this provides a functioning background simulation, the player has **zero direct agency** over individual citizens:
- If a player places a new Farm and needs trees cleared immediately from an adjacent patch, they cannot command a citizen to clear those trees.
- If a player urgently needs a construction site finished before nightfall, they cannot order an idle worker to build it immediately.
- If a player wants to scout an unexplored Point of Interest (POI) near the settlement, they cannot order a citizen to explore that coordinate.
- Selecting a citizen in the inspector and right-clicking anywhere on the world map does absolutely nothing.

This violates `docs/GDD.md` §8.2:
> *"Người chơi có thể chọn dân và ra lệnh: Di chuyển đến vị trí, Chặt cây, Khai thác đá, Khai thác quặng, Vận chuyển, Xây dựng, Canh gác, Khám phá. Lệnh kết thúc khi hoàn thành, bị hủy, không còn mục tiêu hoặc không thể thực hiện. Nếu lệnh thất bại, giao diện phải hiển thị nguyên nhân."*

### The Package 2K Goal:
Implement full **Manual Citizen Command & Direct Labor Dispatch** conforming directly to GDD §8.2 and §8.3, allowing the player to select any citizen and right-click on world tiles, resources, construction sites, and POIs to issue immediate, high-priority manual orders with localized feedback.

---

## 2. DETAILED EXECUTABLE SCOPE

### 2.1. Citizen Command State Machine (`scripts/entities/citizen_controller.gd`)
- **Data Model:**
  Add authoritative manual command tracking dictionary to `CitizenController`:
  ```gdscript
  var manual_command: Dictionary = {
      "type": "",               # "move", "chop", "mine", "build", "haul", "guard", "explore"
      "target_cell": Vector2i(-1, -1),
      "target_id": "",          # building_id, poi_id, or resource key
      "work_hours_required": 0.0,
      "work_hours_done": 0.0,
      "is_active": false
  }
  ```
- **Priority Gating (GDD §8.3 Hierarchy):**
  1. Priority 1 (Emergency Safety): Combat threat / hostile unit adjacent -> flee or defend.
  2. Priority 2 (Vital Survival): Extreme hunger ($\ge 85.0$) or exhaustion ($\ge 90.0$) pauses manual labor to seek food or sleep. Manual order resumes once emergency hunger is relieved.
  3. Priority 3 (Manual Command): Active manual order overrides standard autonomous job seeking.
  4. Priority 4–6: Primary vocation, secondary jobs, idle wandering.
- **Job Release Hygiene:**
  When a manual order is accepted while the citizen has an active autonomous job (`active_job != null`), the citizen immediately releases the job via `job_mgr.release_job(active_job)` so other colony workers can claim it without deadlocks.
- **Command Completion & Cancellation:**
  - Upon reaching target, completing harvest, or finishing construction: clears `manual_command`, emits `manual_command_completed(citizen_id, type)`, awards vocational XP (Package 2B), and transitions cleanly to `State.IDLE`.
  - Public API: `issue_manual_command(type, cell, target_id) -> Dictionary`.
  - Public API: `cancel_manual_command(reason) -> void`.
  - Public API: `has_manual_command() -> bool`.

### 2.2. Interactive World Input Dispatch (`scripts/world/world_view.gd`)
- **Right-Click Targeting Resolution:**
  In `WorldView._unhandled_input()`, when a civilian citizen is selected in the inspector (`inspected_citizen != null`):
  - **Right-click on Walkable Ground:** Issues `move` manual command to `cell`.
  - **Right-click on Forest Tile (`TERRAIN_FOREST`):** Issues `chop` manual command. Citizen moves to adjacent cell, chops tree, and yields Wood directly to settlement inventory.
  - **Right-click on Mountain Tile (`TERRAIN_MOUNTAIN`):** Issues `mine` manual command. Citizen moves to perimeter and mines Stone / Ore.
  - **Right-click on Construction Site (`under_construction`):** Issues `build` manual command, immediately assigning citizen as an active builder on that site.
  - **Right-click on Workplace with Buffer Cargo:** Issues `haul` manual command, ordering citizen to collect buffer goods and transport to Storehouse.
  - **Right-click on Point of Interest (POI):** Issues `explore` manual command, moving citizen to POI perimeter to discover and claim rewards.
- **Fail-Closed Validation & UI Feedback:**
  - If target is out of bounds, unreachable by A* pathfinding, or blocked by water: command rejects with red HUD error banner (`"Lệnh Thất Bại"`, reason).
  - If valid: plays affirmative UI audio tone (`AudioManager.play_click()`) and draws a temporary green diamond target marker at the destination.

### 2.3. HUD Inspector Reflection (`scripts/ui/hud.gd`)
- **Citizen Inspector Badge:**
  In `CitizenInspectPanel`:
  - When `citizen.has_manual_command() == true`:
    - Shows Vietnamese status badge: `"Đang thực hiện lệnh: [Tên Lệnh] (cell: X, Y)"`.
    - Displays progress bar if work hours are required (Chop, Mine, Build).
    - Displays `"Hủy Lệnh"` button (`CancelManualOrderBtn`).
  - Clicking `"Hủy Lệnh"` calls `citizen.cancel_manual_command("Người chơi hủy")` and returns worker to standard routine.

### 2.4. Save/Load Persistence (`scripts/persistence/save_manager.gd`)
- **Schema Compatibility:**
  - Under `citizens` array in save JSON, serialize optional `manual_command` dictionary.
  - `SaveManager.validate_save_data()` validates string types, integer coordinate bounds, and float progress.
  - Legacy saves lacking `manual_command` load cleanly with `manual_command = {"is_active": false}`.
  - Preserves 100% backward compatibility under `SAVE_SCHEMA_VERSION = 1`.

---

## 3. AFFECTED SUBSYSTEMS & FILES

| Subsystem | File Path | Scope of Modification |
|:---|:---|:---|
| **Citizen Entity** | `scripts/entities/citizen_controller.gd` | Manual command dictionary, command state machine, pathing to manual target, harvest/build action ticks, cancel API. |
| **World Interaction** | `scripts/world/world_view.gd` | Unhandled right-click targeting when citizen is inspected, target cell validation, contextual command dispatch, feedback banners. |
| **User Interface** | `scripts/ui/hud.gd` | `CitizenInspectPanel` command badge, progress bar, cancel command button. |
| **Scene UI** | `scenes/ui/hud.tscn` | Inspector layout adjustments for manual command controls. |
| **Persistence** | `scripts/persistence/save_manager.gd` | Serialization, deserialization, and schema validation of `manual_command`. |
| **Test Suite** | `scripts/test/test_manual_citizen_commands.gd` | New comprehensive automated test suite (11+ scenarios). |
| **Test Manifest** | `scripts/test/run_regression.ps1` | Register new test suite in regression manifest (preserving pure ASCII). |

---

## 4. REGRESSION COVERAGE SPECIFICATION

Authored test suite: `scripts/test/test_manual_citizen_commands.gd`

| Scenario ID | Test Name | Invariant Tested |
|:---|:---|:---|
| **TC-MAN.1** | Manual Move Command | Citizen immediately abandons idle/routine and walks to clicked cell. |
| **TC-MAN.2** | Prior Routine Job Clean Release | Dispatching manual command to a working citizen releases `active_job` via `JobManager` without orphaned locks. |
| **TC-MAN.3** | Manual Tree Chopping | Right-clicking forest tile moves citizen to perimeter, chops tree, and credits Wood. |
| **TC-MAN.4** | Manual Rock Mining | Right-clicking mountain tile moves citizen to perimeter, mines stone, and credits Stone. |
| **TC-MAN.5** | Manual Construction Priority | Right-clicking construction site assigns citizen to advance building progress. |
| **TC-MAN.6** | Manual Buffer Hauling | Right-clicking saturated workplace orders citizen to pick up buffer cargo and deliver to Storehouse. |
| **TC-MAN.7** | Manual POI Exploration | Right-clicking POI moves citizen to site, reveals Fog of War, and triggers discovery. |
| **TC-MAN.8** | Survival Need Interruption | Extreme hunger ($\ge 85$) or fatigue ($\ge 90$) safely interrupts manual order to satisfy urgent need, then resumes. |
| **TC-MAN.9** | Manual Order Cancellation | Calling `cancel_manual_command()` halts movement, clears command dictionary, and returns worker to idle. |
| **TC-MAN.10** | Fail-Closed Invalid Target | Right-clicking unreachable water tile or out-of-bounds cell rejects with explicit reason without mutating state. |
| **TC-MAN.11** | Save/Load Roundtrip | Citizen actively executing manual command roundtrips through save/load with identical target cell and progress. |

---

## 5. MANUAL GAMEPLAY ACCEPTANCE CRITERIA

1. **Selection & Command:**
   - Left-click any citizen on map -> `CitizenInspectPanel` opens.
   - Right-click an empty grass tile -> Citizen turns and walks to the tile. Inspector displays `"Đang thực hiện lệnh: Di chuyển (X, Y)"`.
2. **Resource Gathering:**
   - Select an idle citizen -> Right-click an adjacent forest tile -> Citizen walks to the tree, plays work animation, chops wood, and central Wood inventory increases.
3. **Priority Construction:**
   - Place a building construction site -> Select an idle citizen -> Right-click the site -> Citizen immediately walks to the site and begins building.
4. **UI Cancellation:**
   - While citizen is moving to manual destination, click `"Hủy Lệnh"` in inspector -> Citizen immediately halts, clears order, and returns to standard colony routine.
5. **No Teleportation & Obstruction Safety:**
   - Citizens navigate strictly via A* pathfinding; blocked paths show a red error banner without crashing or teleporting.

---

## 6. DEFINITION OF DONE (DoD)

- [x] All 15 automated test scenarios in `test_manual_citizen_commands.gd` pass with Exit Code 0 (97/97 assertions).
- [x] Full regression suite (`run_regression.ps1`) runs 62 suites with 61 PASS, 1 expected baseline failure (`TC-ARMY.32`), and 0 unexpected regressions.
- [x] Save/load persistence roundtrip verified with zero data corruption and full backward compatibility.
- [x] In-Game Player Field Guide (`player_field_guide.gd`) Chương B updated to mention manual right-click commands.
- [x] `docs/quality/BUG_AND_RISK_REGISTER.md` and `docs/WORKLOG.md` synchronized.
- [x] `git diff --cached --check` exits cleanly with 0 whitespace warnings.
- [x] Work committed locally on `feature/package-2k-manual-citizen-commands` without pushing to remote or merging.
