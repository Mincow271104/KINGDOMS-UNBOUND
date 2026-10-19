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
