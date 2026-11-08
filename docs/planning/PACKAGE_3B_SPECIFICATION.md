# KINGDOMS UNBOUND — PACKAGE 3B PROVISIONAL SPECIFICATION
## Campaign Fog of War & Scout Reconnaissance (GDD §3.4, §8.2, §10.4)
### Status: Provisional Draft & Design Decision Register (Awaiting Owner Authorization)

---

### 1. Document Overview & Authoritative Precedence

- **Document Version:** 2.3 (Provisional Draft — Separated Decision Registers & Exact Runtime Baselines)
- **Target Milestone:** Milestone 3 — Strategic Gameplay Complete
- **Package Identifier:** `PACKAGE 3B — CAMPAIGN FOG OF WAR & SCOUT RECONNAISSANCE`
- **Parent Specifications:**
  - `docs/GDD.md` §3.4 (Fog of War: 3 states, distance-based observer sightlines, no complex raymarching)
  - `docs/GDD.md` §7.1 (Watchtower: 1x1 footprint, hazard detection structure)
  - `docs/GDD.md` §8.2 (Citizen Manual Command: Explore / Khám phá)
  - `docs/GDD.md` §10.4 (Strategic Combat Factors: Reconnaissance / Trinh sát contribution to BattleResolver)
  - `docs/GDD.md` §16.3 (Architecture principles & persistence invariants)
  - `docs/SCOPE_DECISIONS.md` §1.13, §1.23, §1.33
- **Primary Objective:** Establish the technical architecture for Fog of War expansion to player-owned territorial outposts, define the boundary between civilian exploration and military reconnaissance, and prepare the GDD §10.4 combat reconnaissance interface without locking in unsupported balance constants prior to owner approval.
- **Implementation Status:** **Specification only.** No production code implementation permitted during this audit turn.

---

### 2. GDD Traceability & Feature Classification Matrix

| Proposed Feature / Mechanic | Exact GDD Evidence | Existing Code Base | Classification | Authoritative Decision |
| :--- | :--- | :--- | :--- | :--- |
| **Three Fog States (`UNEXPLORED`, `EXPLORED`, `VISIBLE`)** | GDD §3.4 explicitly specifies 3 states: Chưa khám phá, Đã khám phá nhưng không quan sát, Đang được quan sát. | Implemented in `scripts/world/fog_of_war.gd` (`enum State { UNEXPLORED, EXPLORED, VISIBLE }`). | **Explicit GDD requirement** / **Existing implemented behavior** | **Approved Scope:** Retain existing architecture. Reuse `FogOfWar` class without creating a duplicate grid. |
| **Distance-Based Observer Sightlines** | GDD §3.4: "Tầm nhìn đơn giản dựa trên khoảng cách từ dân, trạm gác hoặc đội trinh sát. Không cần mô phỏng ánh sáng phức tạp." | Implemented in `FogOfWar.update_observers()` using diamond Manhattan metric $|dx| + |dy| \le r$. | **Explicit GDD requirement** / **Existing implemented behavior** | **Approved Scope:** Retain existing diamond Manhattan distance metric. |
| **Territorial Outpost Vision Projection** | GDD §3.4 (guard stations / trạm gác grant vision), GDD §6.3, GDD §10.5. | `SiegeObjectiveActor` nodes project territorial influence in `TerritoryManager`, but are not yet wired into `WorldView.refresh_world_vision()`. | **Derived technical implementation** | **Approved Scope:** Add player-owned living outposts as vision observers in `WorldView.refresh_world_vision()`. |
| **Outpost Vision Radius** | GDD §3.4 mentions distance from guardposts/scouts, but is silent on numerical radius. | `WorldView.gd` currently uses: Town Hall (10), Citizen (4), Watchtower (15 per `EconomyConfig.BLUEPRINTS`), Army Unit (4). Outpost radius is not set. | **Proposed Derived Technical Value** | **Requires Owner Decision (DEC-3B-01):** Radius 6 proposed to match territory projection; awaiting owner decision. |
| **Civilian Explore vs. Military Scouting** | GDD §8.2 explicitly mandates civilian "Khám phá" (Explore). GDD §10.4 explicitly mandates "Trinh sát" (Reconnaissance) as combat factor. | Civilian Explore delivered in Package 2K (`citizen_controller.gd` + `POIManager`). No dedicated military scout dispatch currently exists. | **Explicit GDD requirement** (Civilian Explore) / **Derived technical implementation** (Military Scouting) | **Approved Scope:** Keep systems decoupled. Package 2K civilian exploration uncovers map tiles and POIs; Package 3B military scouting provides strategic reconnaissance for combat resolution. Dispatch model pending DEC-3B-03. |
| **Combat Reconnaissance Factor** | GDD §10.4: "Kết quả phụ thuộc vào: Quân số, Trang bị, Kinh nghiệm, Công sự, Địa hình, Trinh sát, Tiếp tế..." | `BattleResolver` accounts for troops, equipment, morale, fortification, terrain, but reconnaissance parameter is currently absent. | **Explicit GDD requirement** (Inclusion in Resolver) / **Unspecified Balance Metric** | **Requires Owner Decision (DEC-3B-02):** Wire interface parameter into `BattleResolver`. Numerical modifier values deferred to owner approval. |
| **Tactical Scouting Bonus (+15% for 60s)** | **NOT in GDD.** GDD §10.4 specifies abstract battle simulation, not real-time 60-second buffs. | None. | **Unsupported / Agent assumption** | **REJECTED & REMOVED.** No real-time combat buff timers. |
| **Stale Intelligence & Decaying Records** | GDD §3.4: "Thông tin tài nguyên và công trình của khu vực chưa khám phá không được hiển thị như thể người chơi đã biết." | Standard FoW hides dynamic actors outside `VISIBLE`. Static terrain/buildings persist in `EXPLORED`. | **Unsupported / Agent assumption** | **REJECTED & REMOVED.** Standard FoW rules apply; no artificial expiration timers or question-mark badges needed for MVP. |
| **Fog of War Persistence** | GDD §3.4, GDD §16.3. | `SaveManager` serializes explored coordinates `[[x, y], ...]` in `data["fog_of_war"]` and restores cleanly. | **Existing implemented behavior** | **Approved Scope:** Retain existing serialization. Do not replace working coordinate list with custom bitset. |

---

### 3. Audit of Existing Systems & Integration Points

#### 3.1 Existing Fog of War Grid (`scripts/world/fog_of_war.gd`)
- Fully functional 3-state grid:
  - `State.UNEXPLORED (0)`: Black tile, completely hidden.
  - `State.EXPLORED (1)`: Fogged tile; terrain and discovered static structures visible; dynamic actors hidden.
  - `State.VISIBLE (2)`: Real-time observed tile; all actors and terrain visible.
- Core Methods:
  - `reveal_circle(center: Vector2i, radius: int) -> int`
  - `update_observers(observer_cells: Array, sight_radius: int) -> int`
  - `is_explored(cell: Vector2i) -> bool`, `is_visible(cell: Vector2i) -> bool`
  - `get_explored_ratio() -> float`

#### 3.2 Existing Vision Observers (`scripts/world/world_view.gd`)
- `refresh_world_vision()` executes periodically (hourly simulation tick):
  1. Resets `VISIBLE` to `EXPLORED`.
  2. Evaluates observer positions:
     - Town Hall plaza: `Vector2i(32, 32)`, radius 10.
     - Living citizens: radius 4.
     - Active Watchtowers: radius 15 (`EconomyConfig.BLUEPRINTS["watchtower"]["vision_radius"]`).
     - Tactical army units: radius 4.
  3. Updates `POIManager.update_discovery(fog_of_war)`.

#### 3.3 Genuine Architectural Gaps to Address in Package 3B
1. **Frontier Outpost Gap:** Captured territorial outposts (`SiegeObjectiveActor`) under player control do not contribute vision observers, leaving secured borders dark.
2. **Combat Reconnaissance Gap:** `BattleResolver` has no parameter for GDD §10.4 "Trinh sát" (Reconnaissance). Campaigns launched against targets in unexplored fog execute with identical effectiveness as targets observed in real-time.

---

### 4. Technical Architecture for Package 3B

#### 4.1 Territorial Outpost Vision Integration
- In `WorldView.refresh_world_vision()`, iterate through all player-owned, living territorial outposts (`FieldSiegeManager.get_all_objectives()` where `owning_faction_id == "player"` and `is_alive == true`).
- Each active outpost contributes an observer at `objective.current_cell`:
  - **Proposed Radius:** 6 cells (matches territorial influence radius in `TerritoryManager`).
  - *Pending Owner Approval (DEC-3B-01).*

#### 4.2 Military Reconnaissance & Combat Trigger Definition
- **Provisional Status:**
  - GDD §10.4 mandates reconnaissance ("Trinh sát") qualitatively as a combat consideration, but provides no numerical values.
  - The `0.85` multiplier is strictly a **proposed default**, not an approved rule.
  - Target-cell `is_explored()` as the scouted trigger is a derived architectural proposal.
  - Passive discovery through civilian exploration or army movement is a proposed dispatch model.
  - A dedicated military scout unit is not currently implemented.
- **Definition of "Scouted" Battlefield (Proposed Baseline):**
  A battlefield or target objective cell `C` is defined as:
  - `SCOUTED`: Cell `C` is in state `FogOfWar.State.VISIBLE` or `FogOfWar.State.EXPLORED` (the player has uncovered the target location).
  - `UNSCOUTED` (Blind Attack): Cell `C` is in state `FogOfWar.State.UNEXPLORED` (the player has never observed or mapped the target location).
- **Parties Affected (GDD §10.4 Analysis):**
  - GDD §10.4 lists "Trinh sát" among general battle factors.
  - In military strategy, attacking an unmapped, unexplored objective incurs severe navigational and tactical disadvantages (ambush risk, unknown fortifications).
  - Defenders fighting on their own home territory naturally possess local terrain knowledge. Therefore, the reconnaissance penalty is proposed to apply to the **attacker** launching an offensive into uncharted fog, or dynamically if both sides fight on neutral unexplored ground.
- **Data Contract for Battle System:**
  In `BattleCampaignManager.launch_offensive_campaign()` and `launch_inter_faction_campaign()`:
  - Query `fog_of_war.is_explored(target_cell)`.
  - Pass `"is_scouted": bool` or `"reconnaissance_factor": float` in the `attacker_force` dictionary to `BattleResolver.resolve_battle()`.
  - The exact numerical multiplier is provisional and strictly subject to DEC-3B-02 approval.

#### 4.3 Persistence Architecture (`SaveManager`)
- Retain existing, robust `data["fog_of_war"]` format (array of `[x, y]` coordinates).
- Zero migration risk for existing save files; 100% backward compatible.
- Any future persistent scout mission records will use standard dictionary serialization under `data["military"]`.

---

### 5. Architectural Decision Registers

#### 5.1 Section A: Existing Gameplay Baseline Ratification (DEC-01 through DEC-07)
The following decisions describe existing implemented behavior or established design choices. None of these block Package 3B; each may remain a documented baseline pending a future balance review.

| Decision ID | Domain & Description | Current Runtime Implementation | GDD Source Classification | Current Recommendation | Ratification Status vs. Package 3B |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **DEC-01** | **Outpost Capacity & Defaults** | **Distinction Table Below:**<br>• Constructor default: `3`<br>• Actor exported default: `3`<br>• PAM missing/invalid fallback: `4`<br>• Explicit configured: `N` | GDD §10.1/§10.5 mention outposts qualitatively; no numerical capacity or tier taxonomy in GDD. | **Option A (Documented Baseline):** Retain default 3 (FSM/Actor) and fallback 4 (PAM).<br>**Option B:** Standardize new objectives to 4 in a future authorized change. | **Documented Baseline** (Does not block Package 3B) |
| **DEC-02** | **Civic Fortification Capacities** | Watchtower: `2`, Palisade: `2` in `BuildingSystem.get_building_garrison_capacity()`. | GDD §7.1 defines 1×1 Watchtower; GDD §10.4 mentions fortifications. Numerical capacity is silent. | Retain current capacity of 2 for Watchtower and 2 for Palisade. | **Documented Baseline** (Does not block Package 3B) |
| **DEC-03** | **Defender Combat Modifiers** | Terrain: fixed `1.20`. Fortification: `+0.30`/level in `BattleResolver`. | GDD §10.4 lists "Địa hình" and "Công sự" qualitatively; numerical modifiers are silent. | Retain current `1.20` terrain and `+0.30` fortification multipliers. | **Documented Baseline** (Does not block Package 3B) |
| **DEC-04** | **Soldier Experience in Combat** | Not implemented in `BattleResolver`. Civilian vocational XP exists in `CitizenSkillData`. | GDD §10.4 lists "Kinh nghiệm" qualitatively. | Retain deferral of military XP to post-MVP; focus on core strategic loop. | **Documented Baseline** (Does not block Package 3B) |
| **DEC-05** | **Building Damage Lifecycle Thresholds** | **Absolute HP check (`new_h <= 50`):**<br>• 100% (100 HP): `active`, operational, non-repairable.<br>• 51% (51 HP): `active`, operational, repairable.<br>• 50% (50 HP): `damaged`, disabled, repairable.<br>• 49% (49 HP): `damaged`, disabled, repairable.<br>• 1 HP: `damaged`, disabled, repairable.<br>• 0 HP: `destroyed`, disabled, **strictly non-repairable**. | GDD §7.2 lists states (`Active`, `Damaged`, `Destroyed`) and mandates: *"Chỉ công trình Active mới thực hiện chức năng bình thường"*. Exact threshold is silent. | Retain Package 2M operational lifecycle and non-repairable 0 HP invariant. | **Documented Baseline** (Does not block Package 3B) |
| **DEC-06** | **Repair Economy Cost & Duration** | • Repair cost: `0.25 * damage_ratio * construction_cost`.<br>• Repair duration: `0.50 * damage_ratio * construction_time_hours` (min `2.0`h).<br>• Damage ratio: `(max_h - health) / max_h`.<br>• Demolition salvage: `50%` of construction cost. | GDD §7.3 specifies 50% refund on cancelled construction/demolition. GDD is silent on repair cost and duration percentages (Package 2M design decision; 20% claim repudiated). | Retain Package 2M 25% cost and 50% duration baselines. | **Documented Baseline** (Does not block Package 3B) |
| **DEC-07** | **Soldier Supply Failure Impact** | Daily upkeep: 1 Food/soldier/day at midnight. Failure causes non-lethal morale penalty (80 $\to$ 40) without troop death. | GDD §12.1 lists "Quân đội thiếu tiếp tế" under Decline; silent on soldier starvation death. | Retain non-lethal supply failure to prevent unrecoverable player death spirals. | **Documented Baseline** (Does not block Package 3B) |

##### Detailed Outpost Garrison Runtime Distinction Table (DEC-01):
| Context | Actual Value | Meaning & Runtime Location |
| :--- | :---: | :--- |
| **New objective constructor default** | `3` | Default parameter in `FieldSiegeManager.register_objective(..., garrison: int = 3, ...)` when registering new siege objectives programmatically. |
| **Actor exported default** | `3` | Default value for `@export var garrison_count: int = 3` in `SiegeObjectiveActor` and fallback value in its `deserialize()`. |
| **Invalid/missing legacy data fallback** | `4` | Fallback value in `PlayerArmyManager.get_outpost_info()` line 1382 and `deserialize_garrisons()` lines 1436, 1456, 1685 applied when `obj.garrison_count <= 0` or missing. |
| **Explicitly configured objective** | `N` | Runtime value configured per scene or instance data, clamped by `maxi(1, int(obj.garrison_count))`. |

##### Detailed Building Damage Boundary Behavior (DEC-05):
| Building HP Level | State | Operational Status | Repairable? | System Behavior & Invariants |
| :---: | :---: | :---: | :---: | :--- |
| **100% HP (100/100)** | `active` | Operational | **No** | Full functionality; `can_repair_building()` returns `false` ("Công trình đang ở trạng thái tối ưu"). |
| **51% HP (51/100)** | `active` | Operational | **Yes** | Functions normally; allows preventive maintenance repair before crossing damage threshold. |
| **50% HP (50/100)** | `damaged` | **Disabled** | **Yes** | Operations halt per GDD §7.2; builders can be dispatched for maintenance repair. |
| **49% HP (49/100)** | `damaged` | **Disabled** | **Yes** | Operations halt; builders can repair back to `active`. |
| **1 HP (1/100)** | `damaged` | **Disabled** | **Yes** | Near collapse; operations halt; emergency repair possible. |
| **0 HP (0/100)** | `destroyed` | **Disabled** | **NO** | Total ruin. `can_repair_building()` strictly returns `false` ("Công trình đã bị phá hủy hoàn toàn, không thể sửa chữa"). Must be demolished/rebuilt per GDD §7.2/§7.3. |

---

#### 5.2 Section B: Package 3B Mandatory Implementation Gates (DEC-3B-01 through DEC-3B-04)
The following 4 gates must be formally approved by the project owner prior to beginning Package 3B production code implementation:

| Gate ID | Implementation Gate Description | Proposed Default | Alternative Option | Rationale / GDD Impact | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **DEC-3B-01** | **Outpost Vision Radius** | Radius `6` (matches `TerritoryManager.OUTPOST_RADIUS`) | Radius `5` (conservative) or `8` (matches Town Hall) | GDD §3.4 mandates distance-based vision from guard stations but is silent on numerical value. 6 aligns with established outpost territory influence. | **Pending Owner Approval** |
| **DEC-3B-02** | **Reconnaissance Combat Effect** | Attacker penalty: $\times 0.85$ (15% reduction) if target is in `UNEXPLORED` fog; $\times 1.00$ if scouted. | Additive penalty (e.g. $-10$ combat score) or Defender bonus ($\times 1.15$ if defender has active vision). | GDD §10.4 requires "Trinh sát" to affect outcome. `0.85` is strictly a proposed default, not an approved rule. | **Pending Owner Approval** |
| **DEC-3B-03** | **Scouting Dispatch Model** | Passive/Abstract scouting: Any civilian Explore or army presence revealing the cell satisfies the requirement. | Active dispatch: Dedicated Scout mission dispatched from Barracks costing food/gold and taking travel time. | Passive model reuses Package 2K civilian Explore with zero new unit types, adhering to MVP minimalism (GDD §16.3). | **Pending Owner Approval** |
| **DEC-3B-04** | **Formal Owner Authorization** | Written authorization to begin Package 3B implementation. | Package 3B remains specification-only. | Strict phase-gate control per workspace rules (`AGENTS.md`). | **Pending Owner Approval** |

---

### 6. Exit Gate Criteria for Package 3B

1. **Owner Approval Obtained:** Owner reviews and approves DEC-3B-01 through DEC-3B-04.
2. **Outpost Vision Coverage:** All player-owned territorial outposts project approved vision radius onto `FogOfWar._grid`.
3. **Combat Integration:** `BattleResolver` evaluates the approved reconnaissance factor and reports it in battle explanation.
4. **No Redundant Grids:** Zero duplicate fog grids created; 100% reuse of `FogOfWar` and `IsoMath`.
5. **Save/Load Integrity:** Fog of war state and observer sightlines save and reload identically.
6. **Full Regression Clean:** All 65 existing regression suites continue to pass with 0 failures, Exit Code 0.
