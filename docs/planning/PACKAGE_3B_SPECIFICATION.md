# KINGDOMS UNBOUND — PACKAGE 3B PROVISIONAL SPECIFICATION
## Campaign Fog of War & Scout Reconnaissance (GDD §3.4, §8.2, §10.4)
### Status: Provisional Draft & Design Decision Register (Awaiting Owner Authorization)

---

### 1. Document Overview & Authoritative Precedence

- **Document Version:** 2.1 (Provisional Draft — Unresolved Decisions Separated)
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
| **Outpost Vision Radius** | GDD §3.4 mentions distance from guardposts/scouts, but is silent on numerical radius. | `WorldView.gd` currently uses: Town Hall (10), Citizen (4), Watchtower (15 per `EconomyConfig.BLUEPRINTS`), Army Unit (4). Outpost radius is not set. | **Proposed Derived Technical Value** | **Requires Owner Decision (DEC-3B-01):** Radius 6 proposed to match territory projection; awaiting balance confirmation. |
| **Civilian Explore vs. Military Scouting** | GDD §8.2 explicitly mandates civilian "Khám phá" (Explore). GDD §10.4 explicitly mandates "Trinh sát" (Reconnaissance) as combat factor. | Civilian Explore delivered in Package 2K (`citizen_controller.gd` + `POIManager`). No dedicated military scout dispatch currently exists. | **Explicit GDD requirement** (Civilian Explore) / **Derived technical implementation** (Military Scouting) | **Approved Scope:** Keep systems decoupled. Package 2K civilian exploration uncovers map tiles and POIs; Package 3B military scouting provides strategic reconnaissance for combat resolution. |
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
- **Definition of "Scouted" Battlefield:**
  A battlefield or target objective cell `C` is defined as:
  - `SCOUTED`: Cell `C` is in state `FogOfWar.State.VISIBLE` or `FogOfWar.State.EXPLORED` (the player has uncovered the target location).
  - `UNSCOUTED` (Blind Attack): Cell `C` is in state `FogOfWar.State.UNEXPLORED` (the player has never observed or mapped the target location).
- **Parties Affected (GDD §10.4 Analysis):**
  - GDD §10.4 lists "Trinh sát" among general battle factors.
  - In military strategy, attacking an unmapped, unexplored objective incurs severe navigational and tactical disadvantages (ambush risk, unknown fortifications).
  - Conversely, defenders fighting on their own home territory always possess local terrain knowledge. Therefore, the reconnaissance penalty applies to the **attacker** launching an offensive into uncharted fog, or dynamically if both sides fight on neutral unexplored ground.
- **Data Contract for Battle System:**
  In `BattleCampaignManager.launch_offensive_campaign()` and `launch_inter_faction_campaign()`:
  - Query `fog_of_war.is_explored(target_cell)`.
  - Pass `"is_scouted": bool` or `"reconnaissance_factor": float` in the `attacker_force` dictionary to `BattleResolver.resolve_battle()`.

#### 4.3 Persistence Architecture (`SaveManager`)
- Retain existing, robust `data["fog_of_war"]` format (array of `[x, y]` coordinates).
- Zero migration risk for existing save files; 100% backward compatible.
- Any future persistent scout mission records will use standard dictionary serialization under `data["military"]`.

---

### 5. Package 3B Unresolved Design Decision Register

The following items are **unresolved design decisions** requiring project owner approval prior to implementation:

| ID | Unresolved Design Decision | Proposed Default | Alternative Option | Rationale / GDD Impact |
| :--- | :--- | :--- | :--- | :--- |
| **DEC-3B-01** | **Outpost Vision Radius** | Radius `6` (matches `TerritoryManager.OUTPOST_RADIUS`) | Radius `5` (conservative) or `8` (matches Town Hall) | GDD §3.4 mandates distance-based vision from guard stations but is silent on numerical value. 6 aligns with established outpost territory influence. |
| **DEC-3B-02** | **Reconnaissance Combat Modifier** | Attacker penalty: $\times 0.85$ (15% reduction) if target is in `UNEXPLORED` fog; $\times 1.00$ if scouted. | Additive penalty (e.g. $-10$ combat score) or Defender bonus ($\times 1.15$ if defender has active vision). | GDD §10.4 requires "Trinh sát" to affect outcome. 0.85 is a balanced baseline penalizing blind aggression into the dark. |
| **DEC-3B-03** | **Military Scouting Dispatch Model** | Passive/Abstract scouting: Any civilian Explore or army presence revealing the cell satisfies the requirement. | Active dispatch: Dedicated Scout mission dispatched from Barracks costing food/gold and taking travel time. | Passive model reuses Package 2K civilian Explore with zero new unit types, adhering to MVP minimalism (GDD §16.3). |
| **DEC-3B-04** | **Garrison Manning Vision Synergy** | Manning an outpost with living soldiers (Package 3A) does NOT alter vision radius; vision depends strictly on outpost ownership and structural health. | Stationing $\ge 1$ soldier expands vision radius by $+2$ (e.g. from 6 to 8). | Keeping vision independent of troop count prevents vision flickering during troop rotations. |

---

### 6. Exit Gate Criteria for Package 3B

1. **Owner Approval Obtained:** Owner reviews and approves DEC-3B-01 through DEC-3B-04.
2. **Outpost Vision Coverage:** All player-owned territorial outposts project approved vision radius onto `FogOfWar._grid`.
3. **Combat Integration:** `BattleResolver` evaluates the approved reconnaissance factor and reports it in battle explanation.
4. **No Redundant Grids:** Zero duplicate fog grids created; 100% reuse of `FogOfWar` and `IsoMath`.
5. **Save/Load Integrity:** Fog of war state and observer sightlines save and reload identically.
6. **Full Regression Clean:** All 65 existing regression suites continue to pass with 0 failures, Exit Code 0.
