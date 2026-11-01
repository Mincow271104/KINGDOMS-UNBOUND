# KINGDOMS UNBOUND — System Architecture & Technical Specifications

## Document Overview
- **Status:** Approved Baseline (Phase 0)
- **Engine:** Godot 4.7.stable (Forward+ renderer / Direct3D 12 on Windows)
- **Authority:** Secondary to `MASTER_PROMPT.md` and `docs/GDD.md`.
- **Purpose:** Specifies architectural patterns, layer boundaries, data ownership, coordinate decoupling, scene tree hierarchy, and inter-system API contracts.

---

## 1. Architectural Philosophy & Core Constraints

### 1.1 Strict Simulation vs. Presentation Decoupling
1. **Simulation Domain (Pure Model):**
   - Operates strictly on a $64 \times 64$ discrete integer grid (`Vector2i`).
   - Knows nothing of screen pixels, camera zoom, viewport offsets, textures, or shaders.
   - Authoritative for: tile occupancy, pathfinding, building placement legality, resource inventories, job scheduling, citizen needs, and time progression.
   - Deterministic and testable via headless GDScript runner without spawning visual nodes.

2. **Presentation Domain (View & Interaction):**
   - Converts integer grid cells $(gx, gy)$ to 2:1 dimetric isometric screen space.
   - Ground tiles rendered using Godot 4 `TileMapLayer` with $32 \times 16$ pixel diamond cells.
   - Transforms viewport mouse input to grid coordinates via continuous axis math:
     $$u = \frac{lx}{32.0} + \frac{ly}{16.0}, \quad v = \frac{ly}{16.0} - \frac{lx}{32.0}$$
     $$gx = \lfloor u + 0.5 \rfloor, \quad gy = \lfloor v + 0.5 \rfloor$$
   - Controls entity depth sorting using Godot 2D `y_sort_enabled = true` on the world container and entity layers.

### 1.2 Data Ownership & Unidirectional Data Flow
- **No Direct Mutation:** UI controls, HUD panels, and input handlers NEVER directly mutate simulation data (e.g., resources, citizen stats, building states).
- **Command & Event Pattern:**
  - UI emits user intent commands (e.g., `request_building_placement(type, cell)`, `request_job_priority_change(job, delta)`).
  - Authoritative managers validate commands against game rules, execute state mutations, and emit signals (e.g., `resource_updated`, `building_placed`).
  - UI components listen to signals and refresh read-only display projections.

---

## 2. Autoload Singletons & Core Services

To keep dependencies clean, only truly global services are registered as Autoload singletons:

| Singleton | Script Path | Responsibility |
|---|---|---|
| `MCPRuntime` | `res://addons/godot_mcp/runtime/mcp_runtime.gd` | Godot MCP live runtime inspection and input bridge |
| `TimeManager` | `res://scripts/core/time_manager.gd` | Central game clock, pause state, speed multipliers, hourly/daily/seasonal ticks |
| `ResourceManager` | `res://scripts/economy/resource_manager.gd` | Authoritative resource ledger, storage capacity tracking, atomic reservations |
| `EventManager` | `res://scripts/core/event_manager.gd` | Global decoupled signal routing for world events, notifications, and audio cues |
| `SaveLoadManager` | `res://scripts/persistence/save_load_manager.gd` | Atomic save file serialization, schema versioning, validation, and deserialization |

---

## 3. Scene Tree & Node Hierarchy

```text
Main (Node)
├── World (Node2D, y_sort_enabled = true)
│   ├── TerrainLayer (TileMapLayer, tile_size = (32, 16), diamond)
│   ├── GridCursorHighlight (Polygon2D / Sprite2D, 32x16 diamond preview)
│   ├── Entities (Node2D, y_sort_enabled = true)
│   │   ├── Buildings (Node2D, y_sort_enabled = true)
│   │   │   ├── TownHall (BuildingInstance, 3x3 footprint)
│   │   │   ├── Houses (BuildingInstance, 2x2 footprint)
│   │   │   ├── Farm (BuildingInstance, 2x2 footprint)
│   │   │   ├── Storehouse (BuildingInstance, 2x2 footprint)
│   │   │   └── WoodcutterCamp (BuildingInstance, 2x2 footprint)
│   │   ├── Citizens (Node2D, y_sort_enabled = true)
│   │   │   └── CitizenInstance (Citizen node, foot pivot Vector2(12, 30))
│   │   └── Props (Node2D, y_sort_enabled = true)
│   │       ├── Trees (Base pivot anchored at trunk root)
│   │       └── Rocks (Base pivot anchored at rock base)
│   └── FogOfWarLayer (TileMapLayer / CanvasItem)
├── MainCamera (Camera2D, pan, zoom, map bounds clamp)
└── UI (CanvasLayer)
    ├── HUD
    │   ├── TopBar (TimeControls, DateSeasonDisplay, ResourceLedgerDisplay)
    │   ├── BottomBar (JobAssignmentPanel, BuildMenuPanel, CitizenInspectPanel)
    │   └── CollapseWarningBanner (Conditional alert UI)
    ├── BuildPlacementPreview (Ghost building sprite follows cursor)
    └── ModalDialogs (PauseMenu, SettingsDialog, GameOverSummaryDialog)
```

---

## 4. Entity Architecture & Pivot Anchoring

### 4.1 Ground-Contact Pivots for Flawless Y-Sorting
To ensure entities sort naturally behind and in front of buildings and foliage without z-fighting or pop-in:
1. `World` and `Entities` containers have `y_sort_enabled = true`.
2. **Citizen Entity:**
   - Node position is set to `map_to_local(current_grid_pos)`.
   - Visible sprite is $24 \times 32$ px. Ground contact foot point is at pixel $(12, 30)$.
   - Sprite node has `offset = Vector2(-12, -30)` so that the node origin $(0, 0)$ is precisely at the feet.
3. **Building Entity:**
   - Footprints: $1 \times 1$ ($32 \times 16$ diamond), $2 \times 2$ ($64 \times 32$ diamond), $3 \times 3$ ($96 \times 48$ diamond).
   - Node position is anchored at the bottom-most center vertex of the ground diamond footprint.
   - Sprites extend vertically upwards into $-Y$.
4. **Prop Entity:**
   - Tree/Rock origin is placed at the exact ground intersection point.

---

## 5. Navigation & Job System Architecture

### 5.1 Grid Pathfinding (`GridNavigation`)
- Uses discrete A* pathfinding (`AStar2D` or custom grid A*) on the $64 \times 64$ grid.
- Walkability grid maintained by `GridNavigation`:
  - Terrain cost: Plain/Grass $= 1$, Water/Impassable $= \infty$, Forest $= 2$.
  - Building footprints mark their occupied cells as unwalkable, with access points on perimeter cells.
- Path queries return discrete `Array[Vector2i]`.

### 5.2 Job System (`JobManager`)
- **Job Definition:**
  ```gdscript
  class JobData:
      var id: String
      var job_type: String # "harvest", "build", "haul", "guard"
      var target_cell: Vector2i
      var target_building_id: String
      var required_materials: Dictionary # ResourceID -> Amount
      var state: int # Available, Reserved, InProgress, Completed, Cancelled
      var assigned_worker_id: String
  ```
- **Worker Allocation Lifecycle:**
  1. Citizen enters `Idle` $\to$ queries `JobManager.request_job(worker_skills)`.
  2. `JobManager` finds highest-priority unreserved reachable job.
  3. Job transitions to `Reserved` and locks target cell/resource.
  4. Citizen navigates to target $\to$ state becomes `InProgress`.
  5. On completion, work result is committed, reservations cleared, job transitions to `Completed`.
  6. On failure/unreachable, job transitions to `Available` (with cooldown) or `Cancelled`, worker resets to `Idle`.

---

## 6. Persistence & Serialization Architecture

### 6.1 Save File Format
- File format: Atomic versioned JSON (`user://saves/save_slot_<seed>_<timestamp>.json`).
- Schema versioning:
  ```json
  {
    "schema_version": 1,
    "world_seed": 12345678,
    "game_time": {
      "day": 1,
      "hour": 6,
      "season": "spring",
      "year": 1
    },
    "resources": { ... },
    "buildings": [ ... ],
    "citizens": [ ... ],
    "research": { ... },
    "world_map": { ... }
  }
  ```
- **Atomic Write Safety:**
  - Save file is written first to `.tmp` file (`user://saves/save_temp.json`).
  - Verified via JSON parse and hash check.
  - Renamed atomically to the target save path.
  - Prior good save is copied to `.bak` backup.

---

## 7. GDScript Coding Standards & Conventions
1. **Strong Typing:** All variables, parameters, and return types must be explicitly typed (`func add_resource(type: StringName, amount: int) -> bool:`).
2. **Naming Conventions:**
   - Classes & Types: `PascalCase` (`CitizenController`, `TimeManager`).
   - Files: `snake_case.gd` (`time_manager.gd`, `citizen_controller.gd`).
   - Signals: Past tense or action noun (`resource_changed`, `day_passed`).
   - Constants: `UPPER_SNAKE_CASE` (`MAX_MAP_WIDTH = 64`).
3. **No Hidden State:** No magic global variables; all state mutations flow through documented APIs.

---

## 8. Military & Army Architecture (Packages 1L & 1M)

### 8.1 Standing Army Domain Model (`PlayerArmyManager`)
- **Abstract Numerical Reserve:** `PlayerArmyManager` maintains a centralized standing army reserve (`soldier_count`, `is_supplied`, `last_upkeep_day`). It decouples military recruitment from civilian citizen counts to prevent workforce distortion.
- **Movement State Machine:** Tracks army positioning via `movement_state`: `GARRISONED` (0), `MARCHING` (1), and `IDLE_AT_FIELD` (2).
- **Navigation Integration:** Leverages `GridNavigation` to generate discrete A* routes on the 64×64 logical grid, stepping at 0.5s per cell with simulation clock synchronization.
- **Dynamic Obstruction Rerouting:** Reacts to mid-path collisions by querying `GridNavigation.find_path()` to bypass obstacles or safely halting if isolated.

### 8.2 Presentation & Marker Node (`ArmyMarker`)
- **Single Presentation Node:** `ArmyMarker` extends `Node2D` and renders a gold-uniformed military company with ground pivot `Vector2(-12, -30)` for dimetric Y-sorting.
- **Live Stance Display:** Shows live troop numbers and icon: `🛡️` for garrisoned defense readiness, `⚔️` for field deployment.
- **Smooth Interpolation:** Visual position interpolates smoothly toward authoritative grid coordinates (`IsoMath.map_to_local(current_cell)`), freezing when simulation is paused.

---

## 9. Faction Strategy, Autonomous Diplomacy & Pairwise Relations Architecture (Packages 1Q, 1R, 1S, 1T & 1U)

### 9.1 Layered Faction Decision Pipeline
1. **Authoritative Profile & Status (`FactionData`):** Stores canonical `strategic_goal` (`military_expansion`, `trade_dominance`, `community_growth`, `consolidate_power`) and `existence_status` (`active`, `in_exile`, `eliminated`).
2. **Pairwise NPC-to-NPC Relationship Matrix (`FactionRelationData` & `FactionManager._pairwise_relations`):** Stores canonical unordered NPC faction pairs (`neutral_tribe__rival_merchant`, `neutral_tribe__rival_military`, `rival_merchant__rival_military`) with directional opinions (`opinion_a_to_b`, `opinion_b_to_a`) and shared war/treaty flags (`is_at_war`, `has_nap`, `has_alliance`), completely isolated from player-facing `FactionData` diplomatic fields and settlement raid scheduling.
3. **Pure Autonomous Diplomacy Evaluator (`FactionDiplomacyPlanner`):** Stateless, side-effect-free evaluator (`evaluate_diplomatic_action(fac)`) inspecting `existence_status`, `strategic_goal`, `type`, `is_at_war`, `has_nap`, `has_alliance`, `opinion`, `military_power`, and `stability` against explicit thresholds to return `declare_war`, `sign_peace`, or `none`.
4. **Pure Strategic Intent Evaluator (`FactionStrategyPlanner`):** Stateless, side-effect-free evaluator (`evaluate_faction_intent(fac)`) mapping active faction goals and wartime posture into structured intent dictionaries (`intent_id`, `eligible`, `reason_code`, `posture`).
5. **Bounded Deterministic Executor (`FactionStrategyExecutor`):** Receives `FactionData` and planner decision dictionaries, validates status/goal/cost/cap/idempotency constraints fail-closed, applies atomic resource deductions and clamped attribute deltas, and returns structured execution results (`faction_id`, `day`, `intent_id`, `success`, `reason_code`, `changes`, `posture`).
6. **Daily Coordination & Persistence (`FactionManager` & `SaveManager`):** `FactionManager.update_daily_simulation(day)` runs neutral tribe ascension first, then evaluates and executes autonomous diplomacy (`execute_faction_diplomatic_action(fid, day)`) in sorted alphabetical order (`neutral_tribe`, `rival_merchant`, `rival_military`) emitting `diplomatic_action_evaluated` and `diplomatic_action_executed` while routing war/peace through `declare_war()` and `propose_treaty(..., "peace")`, and finally evaluates and executes active faction strategic intents emitting `strategic_intent_evaluated` and `strategic_intent_executed`. `SaveManager` persists and validates `factions.strategy_executor` (`last_executed_days`, `last_tribe_growth_day`, `last_diplomacy_days`) and `factions.pairwise_relations` to guarantee Save/Load idempotency, anti-oscillation, and fail-closed relational integrity.

---

## 10. Outpost Capture & Territorial Control Architecture (Package 2G)

### 10.1 Authoritative Outpost Domain Model (`SiegeObjectiveActor`)
- **Core Entity Lifecycle:** `SiegeObjectiveActor` (`scripts/combat/siege_objective_actor.gd`) manages physical outpost persistence on the map.
- **State Transition & Idempotency:**
  - `transfer_ownership(new_owner_id, tx_id)` provides atomic mutation guarded against non-empty/whitespace-only transaction IDs, invalid owner IDs (fail-closed if `FactionManager` is null and owner != `"player"`), duplicate transactions (`last_capture_tx_id == tx_id`), and redundant assignment (`owning_faction_id == new_owner_id`).
  - Restores health to `round(max_health * 0.35)`, sets `is_alive = true`, `is_captured = true`, `is_under_active_siege = false`, updates display name, clears defenders, triggers redraw, and emits `objective_ownership_changed(objective_id, prev_owner, new_owner, tx_id)`.
- **Presentation Layer:**
  - `_draw()` renders faction-specific banner colors (Royal Blue for player with golden pole and finials; Crimson Red for military; Amber Gold for merchants; Forest Green for tribes).
  - Health bar renders green for player outposts and red for enemy outposts.

### 10.2 Field Siege Orchestration (`FieldSiegeManager`)
- **Central Coordinator:** `FieldSiegeManager` (`scripts/combat/field_siege_manager.gd`) coordinates player and NPC sieges.
- **Strict Query Invariance:** `can_launch_field_siege()` performs read-only eligibility checks without mutative side-effects or fixture resets.
- **Authoritative Ownership Routing:** `transfer_outpost_ownership(obj_id, new_owner_id, tx_id)` validates owner IDs against known factions and `"player"` (failing closed when `FactionManager` is null for non-player owners), validates `tx_id` non-whitespace, routes to the target objective actor, and emits `outpost_ownership_changed(objective_id, prev_owner, new_owner, tx_id)`.
- **Player Siege Resolution:** Successful player sieges trigger `_resolve_siege_outcome()` with `VICTORY`, invoking `transfer_outpost_ownership(current_objective_id, "player", "player_siege_" + current_siege_id)`.
- **Friendly Siege Prevention:** `can_launch_field_siege()` prevents the player from sieging their own captured outposts.

### 10.3 Inter-Faction Autonomous Warfare Integration (`BattleCampaignManager`)
- **Dynamic Targeting:** `BattleCampaignManager.schedule_inter_faction_campaign()` and `resolve_inter_faction_campaign()` dynamically query live outposts belonging to the defending faction.
- **Objective Sacking:** Attacker victory inflicts real siege damage ($15.0$ HP per surviving troop). When reduced to $\le 0.0\text{ HP}$, the outpost is sacked, transitioning ownership to the attacker via `fsm.transfer_outpost_ownership()`.
- **Active Siege Collision Protection:** Outposts with `is_under_active_siege == true` are strictly bypassed by NPC campaign combat to prevent state races with ongoing player field battles.

### 10.4 Presentation & Event Transparency (`WorldView` & `HUD`)
- **HUD Event Banners:** `WorldView` connects to `field_siege_mgr.outpost_ownership_changed`, surfacing immediate Vietnamese event banners:
  - Player conquest: `"ĐÃ CHIẾM TIỀN ĐỒN! Vương quốc đã làm chủ [Tên Tiền Đồn]!"`
  - NPC conquest: `"BIẾN ĐỘNG LÃNH THỔ! [Phe Tấn Công] đã chiếm đóng [Tên Tiền Đồn] từ tay [Phe Bị Chiếm]!"`

### 10.5 Fail-Closed Persistence & Backward Compatibility (`SaveManager`)
- **Schema Validation:** `SaveManager.validate_save_data()` enforces type safety and bounds for Package 2G metadata (`original_owner_id`, `previous_owner_id`, `capture_revision`, `last_capture_tx_id`).
- **Migration Contract:** Legacy saves missing territorial control metadata initialize safely with original owner equal to `owning_faction_id`, empty previous owner, 0 revision, and empty transaction ID.
