# KINGDOMS UNBOUND — PACKAGE 3B SPECIFICATION
## Campaign Fog of War & Scout Reconnaissance (GDD §3.4, §8.2, §10.4)

---

### 1. Document Overview & Authoritative Precedence

- **Document Version:** 2.0 (Reconciled & GDD-Aligned)
- **Target Milestone:** Milestone 3 — Strategic Gameplay Complete
- **Package Identifier:** `PACKAGE 3B — CAMPAIGN FOG OF WAR & SCOUT RECONNAISSANCE`
- **Parent Specifications:**
  - `docs/GDD.md` §3.4 (Fog of War: 3 states, distance-based observer sightlines, no complex raymarching)
  - `docs/GDD.md` §7.1 (Watchtower: 1x1 footprint, defensive/hazard detection structure)
  - `docs/GDD.md` §8.2 (Citizen Manual Command: Explore / Khám phá)
  - `docs/GDD.md` §10.4 (Strategic Combat Factors: Reconnaissance / Trinh sát contribution to BattleResolver)
  - `docs/SCOPE_DECISIONS.md` §1.13, §1.23, §1.33
- **Primary Objective:** Formally establish the specification for Fog of War expansion to captured territorial outposts, observer sightline consolidation, military reconnaissance integration, and GDD §10.4 combat reconnaissance factor.
- **Implementation Status:** **Specification only.** No production code implementation permitted during this review session.

---

### 2. GDD Traceability & Feature Classification Matrix

| Proposed Feature / Mechanic | Exact GDD Evidence | Existing Code Base | Classification | Authoritative Decision |
| :--- | :--- | :--- | :--- | :--- |
| **Three Fog States (`UNEXPLORED`, `EXPLORED`, `VISIBLE`)** | GDD §3.4 explicitly specifies 3 states: Chưa khám phá, Đã khám phá nhưng không quan sát, Đang được quan sát. | Implemented in `scripts/world/fog_of_war.gd` (`enum State { UNEXPLORED, EXPLORED, VISIBLE }`). | **Explicit GDD requirement** / **Existing implemented behavior** | **Retain existing architecture.** Reuse `FogOfWar` class without creating a duplicate grid. |
| **Distance-Based Observer Sightlines** | GDD §3.4: "Tầm nhìn đơn giản dựa trên khoảng cách từ dân, trạm gác hoặc đội trinh sát. Không cần mô phỏng ánh sáng phức tạp." | Implemented in `FogOfWar.update_observers()` using diamond Manhattan metric $|dx| + |dy| \le r$. | **Explicit GDD requirement** / **Existing implemented behavior** | **Retain existing Manhattan distance metric.** |
| **Territorial Outpost Vision Projection** | GDD §3.4 (guard stations / trạm gác grant vision), GDD §6.3, GDD §10.5. | `SiegeObjectiveActor` nodes project territorial influence in `TerritoryManager`, but are not yet wired into `WorldView.refresh_world_vision()`. | **Derived technical implementation** | **In Scope for Package 3B:** Add player-owned living outposts as vision observers in `WorldView.refresh_world_vision()`. |
| **Observation Radii** | GDD §3.4 mentions distance from citizens, guardposts, scouts, but is silent on exact numerical radii. | `WorldView.gd` currently uses: Town Hall (10), Citizen (4), Watchtower (15 per `EconomyConfig.BLUEPRINTS`), Army Unit (4). | **Derived technical implementation** | **Preserve existing configured baselines.** Avoid arbitrary downgrades (e.g. Watchtower remains 15 per `EconomyConfig`). Outpost radius proposed at 6 (aligned with territory influence); pending owner balance review. |
| **Civilian Explore vs. Military Scouting** | GDD §8.2 explicitly mandates civilian "Khám phá" (Explore). GDD §10.4 explicitly mandates "Trinh sát" (Reconnaissance) as combat factor. | Civilian Explore delivered in Package 2K (`citizen_controller.gd` + `POIManager`). No dedicated military scout dispatch currently exists. | **Explicit GDD requirement** (Civilian Explore) / **Derived technical implementation** (Military Scouting) | **Clearly distinguish systems:** Package 2K civilian exploration uncovers map tiles and POIs; Package 3B military scouting provides strategic reconnaissance for combat resolution. |
| **Combat Reconnaissance Factor** | GDD §10.4: "Kết quả phụ thuộc vào: Quân số, Trang bị, Kinh nghiệm, Công sự, Địa hình, Trinh sát, Tiếp tế..." | `BattleResolver` accounts for troops, equipment, morale, fortification, terrain, but reconnaissance parameter is currently unused (0.0). | **Explicit GDD requirement** | **In Scope for Package 3B:** Wire reconnaissance factor into `BattleResolver.resolve_battle()`. Formula: see Section 4.3 below. |
| **Tactical Scouting Bonus (+15% for 60s)** | **NOT in GDD.** GDD §10.4 specifies abstract battle simulation, not real-time 60-second buffs. | None. | **Unsupported / New design assumption** | **REMOVED from authoritative specification.** Replaced with bounded, turn/day-based reconnaissance factor in `BattleResolver`. |
| **Stale Intelligence & Decaying Records** | GDD §3.4: "Thông tin tài nguyên và công trình của khu vực chưa khám phá không được hiển thị như thể người chơi đã biết." | Standard FoW hides dynamic actors outside `VISIBLE`. Static terrain/buildings persist in `EXPLORED`. | **Unsupported / Agent assumption** | **REMOVED.** Standard FoW rules apply: dynamic entities (armies, caravans) are invisible when in `EXPLORED` fog; no artificial expiration timers or question-mark badges needed for MVP. |
| **Fog of War Persistence** | GDD §3.4, GDD §16.3. | `SaveManager` serializes explored coordinates `[[x, y], ...]` in `data["fog_of_war"]` and restores cleanly. | **Existing implemented behavior** | **Retain existing serialization.** Do not replace working coordinate list with custom bitset. |

---

### 3. Audit of Existing Systems & Integration Points

#### 3.1 Existing Fog of War (`scripts/world/fog_of_war.gd`)
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
- `refresh_world_vision()` executes periodically (hourly tick):
  1. Resets `VISIBLE` to `EXPLORED`.
  2. Evaluates observer positions:
     - Town Hall plaza: `Vector2i(32, 32)`, radius 10.
     - Living citizens: radius 4.
     - Active Watchtowers: radius 15 (`EconomyConfig.BLUEPRINTS["watchtower"]["vision_radius"]`).
     - Tactical army units: radius 4.
  3. Updates `POIManager.update_discovery(fog_of_war)`.

#### 3.3 Functional Gaps to Address in Package 3B
1. **Frontier Outpost Gap:** Captured territorial outposts (`SiegeObjectiveActor`) under player control do not contribute vision observers, leaving secured borders dark.
2. **Combat Reconnaissance Gap:** `BattleResolver` has no parameter for GDD §10.4 "Trinh sát" (Reconnaissance). Campaigns launched against targets in unexplored fog fight with the same effectiveness as targets observed in real-time.

---

### 4. Authoritative Specifications for Package 3B

#### 4.1 Territorial Outpost Vision Integration
- In `WorldView.refresh_world_vision()`, iterate through all player-owned, living territorial outposts (`FieldSiegeManager.get_all_objectives()` where `owning_faction_id == "player"` and `is_alive == true`).
- Each active outpost contributes an observer at `objective.current_cell`:
  - Base Outpost Vision Radius: `6` cells (matching regional territory projection).
  - Garrison Synergy (Optional / Owner Decision): If garrison count $> 0$, vision is fully maintained; if garrison count $== 0$, vision remains at base.

#### 4.2 Military Reconnaissance (GDD §10.4)
- **Distinction from Civilian Explore (Package 2K):**
  - **Civilian Explore:** Issued to a civilian worker to walk toward unexplored coordinates or investigate an undiscovered POI. Worker retreats if danger threatens.
  - **Military Reconnaissance:** An order or campaign preparation step assessing target hostile forces, fortifications, and territory before launching an offensive campaign or raid.
- **Reconnaissance Status:** A target objective or faction territory is considered:
  - `SCOUTED`: Currently within `VISIBLE` or `EXPLORED` fog of war (cell has been revealed).
  - `UNSCOUTED`: Located entirely within `UNEXPLORED` fog (player has never observed the region).

#### 4.3 Combat Reconnaissance Integration (`BattleResolver` & `BattleCampaignManager`)
- In `BattleResolver.resolve_battle()`:
  - Add `reconnaissance_factor: float` to attacker and defender forces.
  - Authoritative values:
    - $\text{Reconnaissance Factor} = 1.00$ when target is in `EXPLORED` or `VISIBLE` territory (scouted target).
    - $\text{Reconnaissance Factor} = 0.85$ when launching an attack into `UNEXPLORED` territory ("Blind Attack" penalty for lack of reconnaissance per GDD §10.4).
  - Formula:
    $$\text{Combat Score}_{\text{atk}} = \text{atk\_troops} \times \text{atk\_equip\_bonus} \times \text{atk\_morale\_factor} \times \text{atk\_recon\_factor} \times \text{variance}$$
  - The battle explanation report in `BattleReport.explanation` notes: *"Tấn công vào vùng chưa trinh sát (-15% hiệu quả chiến đấu)"* if blind attack occurs.

#### 4.4 Persistence Specification (`SaveManager`)
- Retain existing, robust `data["fog_of_war"]` format (array of `[x, y]` coordinates).
- Zero migration risk for existing save files; 100% backward compatible.
- Any future reconnaissance state can be serialized under `data["military"]["reconnaissance"]` if persistent mission timers are introduced.

---

### 5. Exit Gate Criteria for Package 3B

1. **Outpost Vision Coverage:** All player-owned territorial outposts project radius 6 vision onto `FogOfWar._grid`.
2. **Combat Integration:** `BattleResolver` evaluates reconnaissance factor ($1.00$ scouted vs $0.85$ blind attack) and reports it in battle explanation.
3. **No Redundant Grids:** Zero duplicate fog grids created; 100% reuse of `FogOfWar` and `IsoMath`.
4. **Save/Load Integrity:** Fog of war state and observer sightlines save and reload identically.
5. **Full Regression Clean:** All 65 existing regression suites continue to pass with 0 failures, Exit Code 0.
