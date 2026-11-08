# KINGDOMS UNBOUND — PACKAGE 3B SPECIFICATION
## Campaign Fog of War & Scout Reconnaissance (GDD §3.4, §8.2, §10.4, §11.3)

---

### 1. Document Overview & Authoritative Precedence

- **Document Version:** 1.0
- **Target Milestone:** Milestone 3 — Strategic Gameplay Complete
- **Package Identifier:** `PACKAGE 3B — CAMPAIGN FOG OF WAR & SCOUT RECONNAISSANCE`
- **Parent Specifications:**
  - `docs/GDD.md` §3.4 (Fog of War: 3 states, observer sightlines, no complex raymarching)
  - `docs/GDD.md` §7.1 (Watchtower: 1x1 footprint, early hazard warning)
  - `docs/GDD.md` §8.2 (Citizen Manual Command: Explore / Thám hiểm)
  - `docs/GDD.md` §10.4 (Strategic Combat Factors: Reconnaissance contribution to BattleResolver)
  - `docs/GDD.md` §11.3 (Information & Trading Verification)
  - `docs/SCOPE_DECISIONS.md` §1.13, §1.23, §1.33
- **Primary Objective:** Formally establish the specification for Fog of War expansion, outpost/watchtower sightline integration, scout reconnaissance dispatch, stale intelligence lifecycle, and combat integration.
- **Implementation Status:** **Specification only.** No production code implementation permitted during this review session.

---

### 2. Audit of Existing Vision, Exploration & Fog Systems

#### 2.1 Existing Fog of War Architecture (`scripts/world/fog_of_war.gd`)
- **State Model:** Strict 3-state cell grid (`_grid[x][y]`):
  - `State.UNEXPLORED (0)`: Pitch black. Terrains, resources, structures, and units hidden.
  - `State.EXPLORED (1)`: Discovered previously. Terrain and static structures visible (desaturated / grayed out); dynamic entities (armies, citizens, caravans) hidden.
  - `State.VISIBLE (2)`: Currently observed in real-time. All terrain, structures, and dynamic actors rendered.
- **Metric:** Diamond isometric Manhattan distance:
  $$\text{dist}(\vec{a}, \vec{b}) = |a_x - b_x| + |a_y - b_y|$$
- **API:**
  - `reveal_circle(center: Vector2i, radius: int) -> int`
  - `update_observers(observer_cells: Array, sight_radius: int) -> int`
  - `get_explored_ratio() -> float`

#### 2.2 Existing World Vision Observers (`scripts/world/world_view.gd`)
- `refresh_world_vision()` ticks hourly (`_on_simulation_hour_passed`):
  1. Degrades all currently `VISIBLE` cells to `EXPLORED`.
  2. **Town Hall / Starter Plaza:** `Vector2i(32, 32)` with radius `10`.
  3. **Living Citizens:** `current_cell` with radius `4`.
  4. **Active Watchtowers:** `cell` with radius `EconomyConfig.BLUEPRINTS["watchtower"]["vision_radius"]` (default `15`).
  5. **Living Tactical Units:** `current_cell` with radius `4`.
  6. **POIManager Hook:** Calls `poi_mgr.update_discovery(fog_of_war)` and claims POIs when citizens are within distance `2`.

#### 2.3 Existing POI System (`scripts/world/poi_manager.gd`)
- Deterministic POI sites: Ancient Ruins, Abandoned Mine, Sacred Grove, Ancient Shrine.
- Lifecycle: `UNDISCOVERED (0)` $\to$ `DISCOVERED (1)` $\to$ `CLAIMED (2)`.
- Discovery occurs when the POI cell enters `fog_of_war.is_explored(cell)`.

#### 2.4 Existing Save/Load Serialization (`scripts/persistence/save_manager.gd`)
- Fog of War is serialized in `data["fog_of_war"]` as an array of explored 2D coordinates `[[x, y], ...]`.
- On load, restored coordinates are initialized to `State.VISIBLE` or `State.EXPLORED`, and immediately refreshed by `refresh_world_vision()`.

---

### 3. Identified Functional Gaps & Package 3B Scope

| Area | Existing System | Missing Requirement (Package 3B Scope) |
| :--- | :--- | :--- |
| **Outpost Vision** | Only Town Hall & civic Watchtowers grant vision | Player-captured outposts (`SiegeObjectiveActor`, Palisades) do not grant territorial vision |
| **Garrison Sightline Bonus** | Watchtowers grant static radius 15 regardless of garrison | Manning a Watchtower with garrisoned soldiers (Package 3A) does not yet grant vision bonuses |
| **Scout Reconnaissance** | Manual explore command routes individual citizens | No dedicated Scout dispatch to reconnoiter target coordinates, regional outposts, or rival factions |
| **Intel Staleness & Decay** | Vision abruptly toggles between VISIBLE and EXPLORED | No timestamped last-known intel for enemy army sightings or outpost defenses in fog |
| **Combat Intelligence** | `BattleCampaignManager` uses default 0 reconnaissance modifier | GDD §10.4 explicit factor "Trinh sát" is not dynamically wired into `BattleResolver` |
| **Diplomatic Faction Intel** | Faction military power and disposition are globally visible | Faction strength should be obscured or estimated unless territory or outposts have been scouted |

---

### 4. Authoritative Specifications for Package 3B

#### 4.1 Territorial Outpost Vision Integration
- **Objective:** Every captured territorial outpost under player control must project defensive vision into its surrounding chunk/frontier.
- **Vision Radii (Conforming to GDD §3.4 & existing blueprints):**
  - **Player-Owned Outposts (`SiegeObjectiveActor`):**
    - Camp / Village: Radius `6`
    - Town / Fortress: Radius `8`
  - **Palisade (Active):**
    - Base radius: `4` (identical to standard civilian observation)
  - **Watchtower (Active):**
    - Base radius: `15` (per `EconomyConfig.BLUEPRINTS["watchtower"]["vision_radius"]`)
    - **Garrison Manning Bonus:** When 1 or 2 soldiers are stationed at the Watchtower (Package 3A), vision is sharpened, granting an early warning radius expansion (+2 per soldier, max +4).

#### 4.2 Scout Reconnaissance Missions
- **Dispatch Mechanism:**
  - Dispatched via Town Hall or Barracks / PlayerArmyManager.
  - Consumes minimal travel provisions (e.g. food) and dispatches a mobile reconnaissance actor or abstract mission.
  - Missions:
    1. *Sector Reconnaissance:* Scouts a targeted $8 \times 8$ unexplored sector, traveling at high speed and revealing cells along its route.
    2. *Outpost Infiltration:* Scouts a hostile or neutral outpost to assess garrison strength, commander rank, and fortification condition.
- **Safety Invariant:**
  - Scouts are non-combatants in strategic calculations; if intercepted by enemy armies, they retreat with gathered intel or are captured.

#### 4.3 Stale Intelligence & Last-Known Records
- **Data Model:**
  ```gdscript
  class OutpostIntelRecord:
      var outpost_id: String
      var last_observed_day: int
      var last_observed_hour: int
      var observed_owner: String
      var estimated_garrison: int
      var estimated_health: float
      var is_stale: bool # true if (current_day - last_observed_day) > MAX_INTEL_AGE_DAYS
  ```
- **Staleness Expiration:**
  - Intelligence remains fresh for a bounded period (e.g. 3 game-days).
  - After expiration, the outpost status on the map displays a question badge `[?]` and estimated troop brackets instead of exact counts.

#### 4.4 Combat Integration (`BattleResolver` & `BattleCampaignManager`)
- Conforming strictly to GDD §10.4:
  $$\text{Reconnaissance Modifier} = \begin{cases} 
  1.15 & \text{Target recently scouted (fresh intel } \le 24\text{ hours)} \\
  1.00 & \text{Neutral / standard vision} \\
  0.85 & \text{Target completely obscured in Unexplored Fog (Blind Attack)}
  \end{cases}$$
- This directly implements GDD §10.4 ("Kết quả phụ thuộc vào: ... Trinh sát").

#### 4.5 Save/Load Persistence Schema
- Extend `data["fog_of_war"]` and `data["intelligence"]`:
  - `data["fog_of_war"]["explored"]`: array of explored coordinates.
  - `data["intelligence"]["scout_missions"]`: active in-transit reconnaissance missions.
  - `data["intelligence"]["outpost_records"]`: dictionary of last-known outpost intel records.
- Legacy save compatibility: if `intelligence` is missing, defaults cleanly to empty dictionaries without failing validation.

---

### 5. Exit Gate Criteria for Package 3B

1. **Vision Coverage:**
   - Active player outposts, garrisoned watchtowers, and scouts actively update `FogOfWar._grid`.
2. **Deterministic Lifecycle:**
   - Scout dispatch, travel ticks, target reconnaissance, and return follow deterministic hourly increments without instantaneous teleportation.
3. **Combat Traceability:**
   - `BattleResolver` explicitly factors fresh vs blind reconnaissance into combat score and reports it in the battle feedback banner.
4. **Conservation & Idempotency:**
   - Zero scout duplication across save/load.
   - Clean expiration of stale records without memory leakage.
5. **Regression Stability:**
   - 100% pass across all 65 existing test suites plus dedicated Package 3B tests.
