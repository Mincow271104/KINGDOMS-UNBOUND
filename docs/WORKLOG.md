# KINGDOMS UNBOUND — DEVELOPMENT WORKLOG

## [2026-10-12] Milestone 1: Visual Design & Projection Alignment (Documentation Only)

### Context & Objective
Before starting autonomous development under `MASTER_PROMPT.md`, the visual direction was finalized and formalized across authoritative specifications based on the reference artwork `docs/reference/kingdom_visual_reference.png`.

### Completed Work
1. **Authoritative Perspective Specification:**
   - Established the mandatory visual direction: 2D isometric / dimetric, three-quarter top-down pixel art with 2:1 slope (~26.565°).
   - Flat overhead / straight top-down (90° bird's-eye) perspective is explicitly prohibited.
   - Buildings must show visible rooftops (tilted planes facing NW/NE) and front-facing facades (walls facing SW/SE).
2. **Tile Size Evaluation & Decision:**
   - Evaluated 16×8 px diamond (too small, causes visual noise and unreadable textures) and 64×32 px diamond (excessive sprite drawing workload, poor viewport framing at 1080p).
   - Formally standardized on **32 × 16 pixel diamond ground tiles** (2048 × 1024 px world span for a 64×64 grid), providing ideal pixel density, optimal camera framing at 1080p/720p, and crisp 2:1 pixel steps.
3. **Strict Coordinate Decoupling:**
   - The logical 64×64 grid (`Vector2i`) remains pure discrete integer simulation data (unaware of screen pixels, camera zoom, or rendering offsets).
   - The presentation layer projects `(grid_x, grid_y)` to continuous pixel screen coordinates `(screen_x, screen_y)`.
4. **Depth / Y-Sorting Architecture:**
   - Enforced Godot 2D `y_sort_enabled = true` on world parent containers and entity layers.
   - Mandated that every entity node anchor/pivot must be positioned strictly at its ground-contact plane (citizen feet, tree trunk base, building footprint center/base).
5. **Asset Style Guide Creation:**
   - Authored `docs/ASSET_STYLE_GUIDE.md` covering projection geometry, tile dimensions, sprite scales, building footprints (1×1, 2×2, 3×3 diamonds), 27-color core palette, NW directional lighting, selective outlines, animation frame counts, and Godot 4 import settings (Nearest-neighbor, lossless, pixel snapping).
6. **Visual-Validation Gate:**
   - Instituted a mandatory Visual-Validation Gate requiring a dedicated test scene (`res://scenes/test/visual_validation_test.tscn`) verifying terrain, trees, building with visible roof/facade, one moving citizen, diamond grid cursor highlighting, and flawless Y-sorting before producing or integrating large asset collections.
7. **Document Synchronization:**
   - Updated `docs/GDD.md` and `MASTER_PROMPT.md`.

---

## [2026-10-12] Milestone 2: Document Consistency Review & Technical Alignment

### Context & Objective
Rigorous consistency review of all specification documents (`docs/GDD.md`, `MASTER_PROMPT.md`, `docs/ASSET_STYLE_GUIDE.md`, `docs/GDD_REVIEW.md`, `docs/WORKLOG.md`, `AGENTS.md`, and `START_HERE.txt`) to eliminate mathematical ambiguities, reconcile discrepancies, and ensure full implementation readiness.

### Inconsistencies Discovered & Resolutions
1. **Screen-to-Grid Inverse Mapping Inconsistency:**
   - *Issue:* The previous formula used independent `floor()` operations without a $+0.5$ half-tile offset (`floor((screen_x/16 + screen_y/8)/2)`), which incorrectly shifted the tile origin to the top vertex $(0, -8)$ and mapped upper-left interior points of cell $(0, 0)$ to $(-1, 0)$ or $(-1, -1)$. Furthermore, conversion from global mouse coordinates to map-local space was not explicitly stated.
   - *Resolution:* Implemented the mathematically exact transformation using continuous axis coordinates $u = \text{local\_x}/32 + \text{local\_y}/16$ and $v = \text{local\_y}/16 - \text{local\_x}/32$, resolving cells via $\lfloor u + 0.5 \rfloor$ and $\lfloor v + 0.5 \rfloor$. Documented conversion from viewport mouse to map-local space via `tile_map_layer.to_local(mouse_pos)`, documented native Godot 4 `TileMapLayer.local_to_map()` and `map_to_local()` APIs, unified cursor highlight and building placement cell resolution, established map-boundary validation (`0 <= x, y < 64`), and added a comprehensive 13-case validation table across tile centers, off-center interiors, vertices, adjacent cells, and out-of-bounds positions.
2. **Palette-Count Inconsistency:**
   - *Issue:* `docs/WORKLOG.md` erroneously referenced a "40-color master palette", whereas `docs/ASSET_STYLE_GUIDE.md` specified exactly 27 hex color swatches across 5 material ramps.
   - *Resolution:* Standardized on the documented 27 swatches as the authoritative **27-Color Core Fantasy Palette**. Updated `docs/ASSET_STYLE_GUIDE.md` and `docs/WORKLOG.md` accordingly. Added a palette discipline rule specifying that any later secondary tones must interpolate within these 5 ramps rather than introducing arbitrary colors.
3. **Citizen Sprite Specification Variations:**
   - *Issue:* `docs/GDD.md`, `MASTER_PROMPT.md`, and `docs/ASSET_STYLE_GUIDE.md` used slightly varying dimension figures and conflated canvas frame boundaries with visible figure heights.
   - *Resolution:* Established a unified, four-part citizen specification:
     - *Default Sprite Canvas:* 24 × 32 px per frame.
     - *Visible Figure Dimensions:* 12–16 px wide by 22–26 px tall (leaving vertical and horizontal breathing room for hats, bobbing, and tools without canvas distortion).
     - *Ground-Contact Pivot:* `Vector2(12, 30)` within canvas.
     - *World-Space Footprint & Y-Sorting Anchor:* 1×1 logical cell (`Vector2i`), entity node at `map_to_local(cell)`, sprite texture offset at `Vector2(-12, -30)` for exact foot Y-sorting.
     - *Flexibility Clause:* Explicitly declared as a proposed default standard that can be adjusted for non-standard units (mounted units, banners, siege gear) when justified.
4. **Phase Outline Alignment (GDD 0–8 vs. Master Prompt 0–9):**
   - *Issue:* `docs/GDD.md` outline listed 9 phases (Giai đoạn 0–8) while `MASTER_PROMPT.md` outlined 10 phases (Phases 0–9).
   - *Resolution:* Clarified that GDD Giai đoạn 0–8 represents the high-level Game Design Roadmap, while Master Prompt Phases 0–9 represents the operational Technical Execution Workflow. GDD Giai đoạn 7 ("Chiến thắng, sụp đổ và save/load") is intentionally divided into two sequential engineering phases: Phase 7 (Population growth, crisis, prosperity victory, collapse) and Phase 8 (Robust Save/Load & persistence hardening) to isolate data serialization and prevent duplication bugs. Added explicit cross-reference mapping tables to `docs/GDD.md` (Section 18.0), `MASTER_PROMPT.md` (Development Strategy), and `docs/GDD_REVIEW.md` (Section 8).
5. **Path and Filename Consistency:**
   - *Issue:* `docs/GDD_REVIEW.md` referenced `Kingdoms_Unbound_AI_Master_Prompt.md`, which differed from the root file `MASTER_PROMPT.md`. `MASTER_PROMPT.md` line 55 omitted `docs/` prefixes on some document references.
   - *Resolution:* Standardized all references to `MASTER_PROMPT.md` and ensured all documentation paths explicitly include the `docs/` folder prefix.

### Files Changed / Modified
- `docs/ASSET_STYLE_GUIDE.md` (Updated Sections 3.1, 4.2, 4.2.1, 6.1)
- `docs/GDD.md` (Updated Sections 3.1, 18.0)
- `MASTER_PROMPT.md` (Updated Ambiguity references, Phase Mapping subsection, Architecture Rules, Asset Pipeline)
- `docs/GDD_REVIEW.md` (Updated Section 8)
- `docs/WORKLOG.md` (Updated with Milestone 2 review and reconciliation)

### Validations Performed & Results
- **Coordinate Mathematics Validation:** Verified all 13 coordinate test cases mathematically:
  - Centers: $(0, 0) \to (0, 0)$; $(16, 8) \to (1, 0)$; $(-16, 8) \to (0, 1)$; $(0, 16) \to (1, 1)$; $(0, 1008) \to (63, 63)$. All passed.
  - Off-center interiors: $(-8, 0) \to (0, 0)$; $(0, -4) \to (0, 0)$; $(8, 0) \to (0, 0)$; $(0, 4) \to (0, 0)$. All passed.
  - Vertices: $(0, -8) \to (0, 0)$ (half-open boundary).
  - Out-of-bounds: $(0, -8.1) \to (-1, -1)$; $(-32, 0) \to (-1, 1)$; $(0, 1024) \to (64, 64)$. All correctly caught by boundary validation.
- **Palette Swatch Count:** Verified exactly 27 hex codes across 5 categories in `docs/ASSET_STYLE_GUIDE.md`: Foliage (6), Earth (6), Stone (6), Water (5), Accents (4). Sum = 27.
- **Cross-Document Check:** Verified zero broken markdown headings, zero escaped formatting markers (`\#`, `\*\*`), and zero contradictory paths.
- **Implementation Isolation:** Verified `git status` confirming 0 gameplay scripts, 0 scenes, 0 shaders, 0 assets, and 0 engine configs (`project.godot`) were created or altered.

### Outstanding Issues & Conflicts
- None. All specifications are mutually consistent, mathematically validated, and ready for execution.

### Next Exact Step
- Phase 0 Complete. Begin Phase 1 (Vertical Slice).

---

## [2026-10-12] Milestone 3: Phase 0 Audit, Scaffold & Reproducibility (Completed)

### Context & Objective
Execute Phase 0 requirements as mandated by `MASTER_PROMPT.md` and user instructions: lightweight live MCP check, diagnostic recovery, documentation suite creation, `MCPRuntime` autoload verification, and baseline validation using `Godot_v4.7-stable_win64_console.exe`.

### Completed Work
1. **Lightweight MCP Status Check & Diagnostic Recovery:**
   - Identified Godot running idle at Project Manager window without project arguments.
   - Diagnosed via `diagnose_connection`.
   - Launched Godot Editor targeting `E:\KINGDOMS UNBOUND\kingdoms-unbound` with Godot MCP plugin loaded.
   - Verified live MCP connection on port 6505 (`connected: true`, `mode: live`, `addon_version: 1.2.1`).
2. **Project Hygiene & Import Isolation:**
   - Identified import failure on `res://docs/reference/kingdom_visual_reference.png` caused by non-PNG header.
   - Added `docs/.gdignore` to cleanly isolate documentation from Godot asset scanning.
   - Removed orphaned `.import` artifact.
3. **Autoload Verification:**
   - Verified `res://addons/godot_mcp/runtime/mcp_runtime.gd` exists on disk.
   - Added `MCPRuntime="*res://addons/godot_mcp/runtime/mcp_runtime.gd"` to `[autoload]` in `project.godot`.
   - Triggered filesystem rescan via MCP.
4. **Master Document Suite Created:**
   - `docs/SCOPE_DECISIONS.md`: Resolved all 10 Master Prompt ambiguities and established starter resource/job rules.
   - `docs/GAME_RULES.md`: Mathematical formulas for 2:1 dimetric projection, simulation ticks, needs decay, seasons, victory/collapse.
   - `docs/ARCHITECTURE.md`: Pure 64×64 simulation coordinate decoupling, scene tree hierarchy, Y-sorting pivots, data contracts.
   - `docs/IMPLEMENTATION_PLAN.md`: 10-phase execution roadmap mapping directly to GDD Phases 0–8.
   - `docs/TEST_PLAN.md`: Headless and MCP test harness, test suites TC-0.1 through TC-9.1.
   - `docs/BACKLOG.md`: Task tracker with `[ ]`, `[-]`, `[x]` status markers.
   - `docs/KNOWN_ISSUES.md`: Issue register with symptoms, causes, and verified fixes.
   - `docs/CHANGELOG.md`: Versioned user-visible changelog.
   - `docs/NIGHTLY_REPORT.md`: Autonomous execution summary.

### Validations Performed & Results
- **TC-0.1 Headless Scan:** Executed `Godot_v4.7-stable_win64_console.exe --headless --editor --path "E:\KINGDOMS UNBOUND\kingdoms-unbound" --quit`. Result: Exit code 0, 0 parse errors, 0 asset errors.
- **TC-0.2 MCP Live Bridge:** Verified via `get_godot_status` and `diagnose_connection`: connected to `E:/KINGDOMS UNBOUND/kingdoms-unbound/`, port 6505, healthy.

### Phase 0 Exit Gate Assessment
- **Status: PASSED.** Project imports, opens, and connects to tooling with zero errors. All required documents are populated and committed to disk.

### Next Exact Step
- Phase 0 Complete. Begin Phase 1 (Vertical Slice).

---

## [2026-10-12] Milestone 4: Phase 1 Vertical Slice & Visual-Validation Gate (Completed)

### Context & Objective
Implement Phase 1 Vertical Slice as mandated by `MASTER_PROMPT.md`:
- Main menu scene with New World, Settings, Quit.
- Seeded procedural 64×64 logical grid map rendered in 2D dimetric (2:1 isometric) projection with 32×16 diamond ground tiles.
- Starter building instances (Town Hall 3×3, 4 Houses 2×2, Farm 2×2, Storehouse 2×2, Woodcutter Camp 2×2) with visible roofs and SW/SE facades.
- CameraController with pan, zoom, and bounding box clamping.
- Central `TimeManager` autoload with pause safety and speed multipliers (0x, 1x, 2x, 3x).
- Interactive mouse-hover diamond tile highlight.
- Mandatory **Visual-Validation Gate Scene (`res://scenes/test/visual_validation_test.tscn`)** demonstrating terrain, props, multi-tile building, moving citizen, diamond cursor highlight, and flawless Y-sorting.

### Completed Work
1. **Mathematical Coordinate Decoupling:**
   - Implemented `scripts/utils/iso_math.gd` with forward/inverse 2:1 dimetric functions, bounding box queries, and neighbor lookups.
   - Verified via unit test `scripts/test/test_coordinates.gd` (TC-1.1): all 13 reference coordinate cases passed.
2. **Central Simulation Clock:**
   - Implemented `scripts/core/time_manager.gd` autoload singleton with pause safety, speed controls (0x–3x), hourly/daily/seasonal ticks, and calendar formatting.
   - Registered in `project.godot` autoload.
   - Verified via unit test `scripts/test/test_time_manager.gd` (TC-1.4).
3. **Procedural Pixel Art Pipeline:**
   - Implemented `scripts/tools/generate_pixel_assets.gd` conforming strictly to `docs/ASSET_STYLE_GUIDE.md` and 27-color palette.
   - Generated 13 pixel-perfect assets: terrain tiles (grass, dirt, water, sand), props (tree, rock), buildings (townhall, house, farm, storehouse, woodcutter), citizen sprite (24×32 canvas, foot pivot at (12, 30)), and diamond cursor outline.
4. **Deterministic Seeded World Generation:**
   - Implemented `scripts/world/world_generator.gd` generating 64×64 simulation grid with FastNoiseLite elevation, island shaping, dry central plaza, and deterministic placement of all 8 starter buildings and flora.
   - Verified via unit test `scripts/test/test_world_gen.gd` (TC-1.2): 100% byte-for-byte identical terrain and props across identical seed runs.
5. **Mandatory Visual-Validation Gate Scene:**
   - Delivered `scenes/test/visual_validation_test.tscn` and `scripts/test/visual_validation_test.gd`.
   - Verified 32×16 diamond terrain, multi-tile building with visible rooftop/facade, isometric props, 1 moving citizen with ground-contact foot pivot, interactive hover cursor, and flawless Y-sorting behind and in front of buildings.
   - Captured runtime screenshot (`screenshot_3162.png`) and visually verified natural occlusion.
6. **Full In-Game World & HUD:**
   - Implemented `scripts/world/world_view.gd` and `scenes/world/world_view.tscn`.
   - Implemented `scripts/ui/hud.gd` and `scenes/ui/hud.tscn` with time controls, clock, resource ledger, and pause menu.
   - Implemented `scripts/ui/main_menu.gd` and `scenes/ui/main_menu.tscn`.
   - Configured `run/main_scene="res://scenes/ui/main_menu.tscn"` in `project.godot`.
   - Captured runtime screenshot (`screenshot_3547.png`) verifying 64×64 isometric world, starter settlement, HUD, and 24 citizens.

### Validations Performed & Results
- **TC-1.1 Coordinate Transform:** **PASS** (13/13 cases passed).
- **TC-1.2 World Generation Reproducibility:** **PASS** (Identical seed produces identical 64×64 map; 0 building collisions).
- **TC-1.3 Visual-Validation Gate:** **PASS** (Headless check passed, runtime screenshot 3162 inspected).
- **TC-1.4 TimeManager & Pause Safety:** **PASS** (1 real sec = 1 game hour, pause stops all simulation, seasonal modifiers correct).
- **Project Headless Launch:** **PASS** (Exit code 0, 0 parse/import errors).

### Phase 1 Exit Gate Assessment
- **Status: PASSED.** All requirements of Phase 1 and the Visual-Validation Gate are fully satisfied, tested, and visually confirmed.

### Next Exact Step
- Phase 1 Complete. Begin Phase 2 (Authoritative Economy).

---

## [2026-10-12] Milestone 5: Phase 2 Authoritative Resources, Buildings & Economy (Completed)

### Context & Objective
Implement Phase 2 authoritative economy systems as mandated by `MASTER_PROMPT.md`:
- Data-driven resource definitions using stable string/enum IDs (Food, Wood, Stone, Ore, Metal, Tools, Crystal, Herbs, Gold).
- Single authoritative `ResourceManager` ledger; no UI directly mutates resources.
- Starting quantities from GDD ($150$ Food, $120$ Wood, $60$ Stone, $200$ Gold, etc.).
- Centralized data-driven building blueprints (`EconomyConfig.BLUEPRINTS`).
- Functional building placement validation (boundary, water check, occupancy collision, cost affordability).
- Atomic resource reservation preventing double-spending.
- Storage capacity limits enforcement.
- Daily food consumption tick ($0.8 \times 24 = 19.2 \approx 20$ Food/day).
- Interactive In-Game Build Menu and ghost building placement preview.

### Completed Work
1. **Data-Driven Economy Configuration:**
   - Authored `scripts/economy/economy_config.gd` defining all 9 resource stable IDs, Vietnamese localized display names, GDD starting inventory, base storage capacities, and complete building blueprints for House, Storehouse, Farm, Woodcutter Camp, and Town Hall.
2. **Authoritative Resource Ledger:**
   - Implemented `scripts/economy/resource_manager.gd` autoload singleton with atomic cost locking (`reserve_cost`), deduction (`commit_cost`), and cancellation (`release_cost`).
   - Registered `ResourceManager` in `project.godot` autoload.
   - Wired live resource update signals (`resource_changed`, `capacity_changed`, `deficit_warning`).
3. **Building Placement & Construction System:**
   - Implemented `scripts/economy/building_system.gd` enforcing discrete grid bounds, water prohibition, occupancy tracking, and storage capacity expansion.
   - Supports demolition with material refunds.
4. **Interactive In-Game Build Menu:**
   - Updated `scenes/ui/hud.tscn` and `scripts/ui/hud.gd` with Build button (`🏗️ Xây Dựng (B)`) and Build Menu panel.
   - Updated `scripts/world/world_view.gd` with real-time ghost building placement preview showing green (legal) and red (blocked) states, left-click placement, and right-click cancellation.
5. **Headless Economy Automated Test Suite:**
   - Authored `scripts/test/test_economy.gd` (TC-2.1 and TC-2.2).
   - Validated: starting quantities, storage cap limits, atomic reservation, double-spending prevention, all-or-nothing cost reservation, building placement single deduction, footprint collision rejection, water placement rejection, and daily food upkeep consumption.

### Validations Performed & Results
- **TC-2.1 Resource Ledger & Reservations:** **PASS** (Storage caps enforced, atomic reservation verified, double-spending prevented).
- **TC-2.2 Building Placement & Deduction:** **PASS** (Costs deducted exactly once, collisions and water rejected).
- **Full Regression Suite:** TC-0.1, TC-0.2, TC-1.1, TC-1.2, TC-1.3, TC-1.4, TC-2.1, TC-2.2 all passed with 0 failures.
- **Runtime Screenshot:** Screenshot `screenshot_3466.png` verified in-game HUD with Build button and resource counts.

### Phase 2 Exit Gate Assessment
- **Status: PASSED.** Build costs charged exactly once; invalid builds fail safely; storage limits enforced; no resource spent twice; scripted economy test passes completely.

### Next Exact Step
- Execute Phase 2 local Git checkpoint.
- Proceed to **Phase 3: Citizens, Navigation & Real Jobs**.

---

## [2026-10-12] Milestone 6: Phase 3 Citizens, Navigation & Real Jobs (Completed)

### Context & Objective
Implement Phase 3 autonomous simulation layer as mandated by `MASTER_PROMPT.md` and `docs/GDD.md`:
- Pure 2D discrete A* grid pathfinder (`scripts/navigation/grid_navigation.gd`) operating on 64×64 simulation grid with 4-way/diagonal movement and obstacle avoidance.
- Shared job system (`scripts/jobs/job_manager.gd`) with lifecycle (`AVAILABLE` $\to$ `RESERVED` $\to$ `IN_PROGRESS` $\to$ `COMPLETED` / `CANCELLED`).
- Citizen controller (`scripts/entities/citizen_controller.gd`) and scene (`scenes/entities/citizen.tscn`) with foot pivot at $(12, 30)$ for pixel-accurate Y-sorting.
- Spawn exactly 24 starter citizens with unique stable IDs and jobs conforming to `docs/SCOPE_DECISIONS.md`: 5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle.
- Need decay simulation (Hunger, Fatigue, Health, Morale) ticking hourly.
- In-game Citizen Inspection Panel in HUD showing citizen name, job, needs, active path, and state.
- Automated headless test suite `scripts/test/test_citizens.gd` (TC-3.1 and TC-3.2).

### Completed Work
1. **Discrete Grid A* Pathfinding:**
   - Implemented `scripts/navigation/grid_navigation.gd` using Manhattan distance heuristic, dynamic walkability evaluation (water, building footprint obstacles), and fail-safe recovery for unreachable destinations.
2. **Authoritative Job Manager:**
   - Implemented `scripts/jobs/job_manager.gd` tracking registered workplaces, workplace employee quotas, dynamic building construction jobs, and job reservation/progress/completion lifecycles.
3. **Citizen Controller & State Machine:**
   - Implemented `scripts/entities/citizen_controller.gd` with states: `IDLE`, `MOVING_TO_JOB`, `WORKING`, `SEEKING_FOOD`, `RESTING`.
   - Wired hourly needs decay: Hunger (-2/hr), Fatigue (-1.5/hr).
   - Autonomous job seeking, movement along A* waypoints, working at site, and returning to idle.
4. **Starter Settlement Citizen Deployment:**
   - Instantiated 24 starter citizens in `scripts/world/world_view.gd` with unique IDs (`cit_001` through `cit_024`) and starter professions: 5 Farmers assigned to Farm, 4 Woodcutters to Woodcutter Camp, 3 Builders, 3 Haulers, 9 Idle.
   - Interactive citizen selection via mouse click in `world_view.gd`.
5. **HUD Citizen Inspection Panel:**
   - Added Citizen Info Panel in `scenes/ui/hud.tscn` and `scripts/ui/hud.gd` displaying Citizen Name, Role, Current State, Needs progress bars (Hunger, Fatigue, Health, Morale), and Current Destination.
6. **Automated Test Suite:**
   - Created `scripts/test/test_citizens.gd` validating: 24 citizen configuration & professions, unique IDs, A* path navigation, unreachable target safe handling, job claim & reservation, job progression, and completion back to IDLE.

### Validations Performed & Results
- **TC-3.1 A* Pathfinding & Reachability:** **PASS** (13-step path resolved around obstacles; unreachable target returns empty path cleanly without crashing or infinite looping).
- **TC-3.2 24 Citizen Spawn & Job Allocation:** **PASS** (Exactly 24 citizens: 5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle; 24 unique IDs).
- **Job Lifecycle Execution:** **PASS** (Job reserved, progressed, completed; worker returns to IDLE).
- **Full Regression Test:** TC-0.1, TC-0.2, TC-1.1, TC-1.2, TC-1.3, TC-1.4, TC-2.1, TC-2.2, TC-3.1, TC-3.2 all pass with 0 failures.
- **Runtime Visual Inspection:** Screenshot `screenshot_104607.png` verified 24 moving citizens on 64×64 isometric world, hunger consumption over 5 game days, and 0 runtime errors.

### Phase 3 Exit Gate Assessment
- **Status: PASSED.** 24 citizens spawn with assigned jobs; pathfinding resolves paths around obstacles; job lifecycle transitions cleanly; citizen inspection panel renders live; scripted tests pass completely.

### Next Exact Step
- Execute Phase 3 local Git checkpoint.
- Proceed to **Phase 4: Working Logistics Loop & Basic Automation**.

---

## [2026-10-12] Milestone 7: Phase 4 Working Logistics Loop & Basic Automation (Completed)

### Context & Objective
Implement Phase 4 logistics loop, consumption ticks, and priority automation as mandated by `MASTER_PROMPT.md` and `docs/GDD.md`:
- Physical hauling loop: workplace production deposited locally in output buffers (Farm: 50 food buffer, Woodcutter: 40 wood buffer) rather than instant teleportation into central inventory.
- Haulers physically traverse to workplaces, pick up cargo, navigate to Storehouse/Town Hall dropoffs, and deposit items.
- Seasonal agriculture modifier: $1.2\times$ Summer, $0.5\times$ Winter, $1.0\times$ Spring/Autumn.
- Non-instant starvation escalation: food depletion triggers "Nạn đói" state; morale drops by -15/day, fatigue +20/day, health drops 5%/day; death only at health 0; natural recovery when fed.
- Priority automation rules with strict execution budget ($O(1)$ constant overhead) to prevent performance death spirals.
- Automated headless test suite `scripts/test/test_logistics.gd` (TC-4.1, TC-4.2, TC-4.3).

### Completed Work
1. **Workplace Output Buffers & Access Points:**
   - Implemented `scripts/economy/workplace_manager.gd` managing local output buffers, worker production cycles with seasonal modifiers, and nearest dropoff resolution.
   - Farm buffer max: 50 Food; Woodcutter buffer max: 40 Wood.
2. **Physical Hauler Logistics Loop:**
   - Updated `scripts/jobs/job_manager.gd` with priority scoring, recurring workstation slots, and dedicated `create_hauling_job` methods.
   - Updated `scripts/entities/citizen_controller.gd` with `State.HAULING`, cargo pickup from workplace buffer, physical travel to dropoff, and deposit to `ResourceManager`.
3. **Seasonal Agriculture & Starvation Escalation:**
   - Integrated `TimeManager.get_seasonal_farm_modifier()` ($1.2\times$ Summer, $0.5\times$ Winter).
   - Enhanced `ResourceManager` with `is_starving()` and active daily food upkeep deductions ($0.8 \times 24 = 19.2 \approx 20$ food/day).
   - Citizen controller implements non-instant starvation: health decays at $0.208\%$/hour (~$5\%$/day) only during starvation, recovering by $+0.417\%$/hour when fed.
4. **Priority Automation System with Execution Budget:**
   - Implemented `scripts/economy/automation_manager.gd` with `evaluate_rules` enforcing `MAX_RULE_CHECKS_PER_TICK = 10`.
   - Rule 1: Emergency Food Priority Boost (food $< 30 \implies$ boost farmer & hauler priorities).
   - Rule 2: Workplace Buffer Congestion Protection (buffer $\ge 80\% \implies$ boost hauler priority).
   - Rule 3: Autumn Winter Preparation (food $< 80 \implies$ boost food production).
5. **HUD & World View Integration:**
   - Integrated `workplace_mgr` and `automation_mgr` into `scripts/world/world_view.gd` with hourly simulation updates.
   - Updated HUD citizen inspector to display carried cargo (`scripts/ui/hud.gd`).
6. **Automated Test Suite:**
   - Created `scripts/test/test_logistics.gd` validating physical hauling without teleportation, seasonal modifiers (Summer: 6 > Winter: 3), non-instant starvation (health drops to 95% after 24h, no instant death), natural recovery, and automation execution budget (2 / 10 checks used).

### Validations Performed & Results
- **TC-4.1 Physical Hauling vs Teleportation:** **PASS** (Workplace buffers hold goods locally; central storage updates only upon physical dropoff by hauler).
- **TC-4.2 Seasonal Modifiers & Non-Instant Starvation:** **PASS** (Summer 1.2x > Winter 0.5x; 24h starvation does not kill citizen; health recovers when fed).
- **TC-4.3 Automation Rules & Execution Budget:** **PASS** (Emergency rule triggers; budget capped at 10 checks; no performance spirals).
- **Full Regression Test:** TC-0.1, TC-0.2, TC-1.1, TC-1.2, TC-1.3, TC-1.4, TC-2.1, TC-2.2, TC-3.1, TC-3.2, TC-4.1, TC-4.2, TC-4.3 all passed with 0 failures.
- **Runtime Visual Inspection:** Screenshot `screenshot_6682.png` verified active simulation, citizens working and hauling, time progressing across hours, and 0 runtime errors.

### Phase 4 Exit Gate Assessment
- **Status: PASSED.** Food produced at farm is physically hauled to storage; seasonal modifiers visibly scale farm output; starvation escalates non-instantly; automation rules operate within budget; scripted tests pass completely.

### Next Exact Step
- Execute Phase 4 local Git checkpoint.
- Proceed to **Phase 5: Research, Exploration & Events**.

---

## [2026-10-12] Milestone 8: Phase 5 Research, Exploration & Events (Completed)

### Context & Objective
Implement Phase 5 research tree, exploration/Fog of War, Points of Interest (POIs), and world event system per `MASTER_PROMPT.md` and `docs/GDD.md`:
- Tech tree with 4 branches (survival, production, military, mysticism) and 10 technologies with prerequisites and atomic resource deductions.
- Single active research project constraint per GDD 9.3; pause safety.
- 3-state Fog of War grid (UNEXPLORED, EXPLORED, VISIBLE) per GDD 3.4.
- Deterministic POI exploration sites with single-claim persistent discovery rewards (preventing double-claiming).
- Periodic colony world events with deterministic cooldown intervals and decoupled event dispatch.
- In-Game HUD Royal Research Institute panel (`KEY_T`), Research button, and Event Banner.
- Automated test suite `scripts/test/test_research_and_exploration.gd` (TC-5.1, TC-5.2, TC-5.3).

### Completed Work
1. **Technology Tree & Research Manager:**
   - Created `scripts/research/tech_tree.gd` defining 4 branches and 10 technologies with prerequisites, resource costs, and research durations.
   - Implemented `scripts/research/research_manager.gd` enforcing single active project constraint, atomic resource deduction, 50% cancellation refund, pause safety, and bonus applications (e.g. +500 storage capacity, +25% research speed).
2. **Fog of War 3-State Simulation:**
   - Implemented `scripts/world/fog_of_war.gd` supporting `UNEXPLORED` (0), `EXPLORED` (1), and `VISIBLE` (2), diamond radius vision reveals, and state degradation.
3. **Points of Interest (POI) Management:**
   - Created `scripts/world/poi_manager.gd` placing deterministic exploration sites (Ancient Ruins, Abandoned Mines, Sacred Groves, Ancient Shrines) on walkable cells outside the central settlement.
   - Enforced single-claim rule: reward claimed atomically into storage once; subsequent claims rejected.
   - Created pixel art asset `assets/props/prop_poi_ruins.png`.
4. **World Event System & EventManager Autoload:**
   - Created `scripts/core/world_event_system.gd` with positive and negative events and cooldown intervals.
   - Registered `scripts/core/event_manager.gd` autoload in `project.godot` routing decoupled world alerts.
5. **HUD & World View Integration:**
   - Added `ResearchBtn`, `ResearchMenuPanel` ("VIỆN NGHIÊN CỨU HOÀNG GIA"), and `EventBanner` to `scenes/ui/hud.tscn`.
   - Wired `scripts/ui/hud.gd` with live research progress, interactive research buttons, `KEY_T` shortcut, and event banners.
   - Updated `scripts/world/world_view.gd` instantiating research, fog of war, POI nodes, citizen vision updates, POI reward claiming, and daily event triggers.
6. **Automated Test Suite & Verification:**
   - Authored `scripts/test/test_research_and_exploration.gd` validating TC-5.1, TC-5.2, and TC-5.3.
   - Visual verification via Direct3D 12 render runtime: captured screenshots `screenshot_phase5.png` (world view with POIs and Research button) and `screenshot_phase5_research_menu.png` (open Royal Research Institute dialog).

### Validations Performed & Results
- **TC-5.1 Tech Tree Prerequisites & Deductions:** **PASS** (Prerequisites strictly enforced; atomic cost deductions verified; single active project limit enforced; unlocks work).
- **TC-5.2 Fog of War & POI Exploration:** **PASS** (3-state grid initialized to UNEXPLORED; sight radius marks VISIBLE; degradation to EXPLORED verified; POIs discovered upon fog exploration; single-claim enforced, double-spend rejected).
- **TC-5.3 World Event Triggers & Cooldowns:** **PASS** (Periodic events trigger, apply resource effects, dispatch via EventManager, and obey cooldown intervals).
- **Full Regression Test Matrix:** TC-0.1, TC-0.2, TC-1.1, TC-1.2, TC-1.3, TC-1.4, TC-2.1, TC-2.2, TC-3.1, TC-3.2, TC-4.1, TC-4.2, TC-4.3, TC-5.1, TC-5.2, TC-5.3 all passed with exit code 0.
- **Runtime Visual Inspection:** Screenshots `screenshot_phase5.png` and `screenshot_phase5_research_menu.png` verified with 0 runtime errors.

### Phase 5 Exit Gate Assessment
- **Status: PASSED.** 4 research branches operational; single-project constraint strictly obeyed; 3-state Fog of War and deterministic POIs working with single-claim persistent rewards; world events dispatching; scripted tests 100% passed.

### Next Exact Step
- Execute Phase 5 local Git checkpoint.
- Proceed to **Phase 6: Factions, Diplomacy, Trade & Abstract Battles** (Task 6.1: 2 rival factions and 1 neutral faction with deterministic states; scheduled trade caravans; deterministic battle resolver).

---

## [2026-10-12] Milestone 9: Phase 6 Factions, Diplomacy, Trade & Abstract Battles (Completed)

### Context & Objective
Implement Phase 6 external factions, diplomatic treaties, visiting merchant caravans, and deterministic battle resolver per `MASTER_PROMPT.md` and `docs/GDD.md`:
- 2 rival factions ("Cổ Thành Thiết Giáp", "Thương Hội Vân Đồn") and 1 neutral faction ("Bản Làng Rừng Xanh") with deterministic states.
- Diplomatic state machine: Non-Aggression Pacts (NAP), Alliances, Gifts/Tribute, War declarations, Peace treaties.
- Scheduled trade caravans with finite inventory, asymmetric buy/sell pricing, faction opinion modifiers, and atomic exchange transactions.
- Deterministic abstract battle resolver (`BattleResolver.gd`) calculating casualties, plunder spoils, fortification impact, and explainable outcome reports.
- In-Game HUD Royal Diplomacy & Trade modal (`KEY_Y`) and BottomBar navigation button.
- Automated test suite `scripts/test/test_factions_and_battles.gd` (TC-6.1 & TC-6.2).

### Completed Work
1. **Faction Data & Diplomacy Manager:**
   - Implemented `scripts/factions/faction_data.gd` modeling disposition (`HOSTILE`, `NEUTRAL`, `FRIENDLY`, `ALLIED`), opinion (-100 to +100), military power, stability, population, and active treaties.
   - Implemented `scripts/factions/faction_manager.gd` with gift sending, treaty negotiations (NAP requires opinion $\ge 0$, Alliance requires opinion $\ge 60$), war declarations, peace accords, and neutral tribe evolution checks.
2. **Trade Caravans & Atomic Transactions:**
   - Implemented `scripts/trade/trade_caravan.gd` with deterministic seeded arrivals, finite item stocks, gold budgets, asymmetric buy/sell pricing, opinion discounts, and atomic all-or-nothing transactions preventing item/gold duplication.
3. **Deterministic Battle Resolver:**
   - Implemented `scripts/combat/battle_resolver.gd` calculating combat scores from troops, equipment tiers (1–3), morale, fortification levels (0–3), and terrain multipliers.
   - Formulated proportional casualty distributions (winner 8–25%, loser 35–70%) and plunder spoils (20% of defender stock).
   - Generates comprehensive `BattleReport` with explainable outcome reasons.
4. **HUD & World View Integration:**
   - Added `DiplomacyBtn` ("👑 Ngoại Giao (Y)") to HUD bottom bar and `DiplomacyPanel` ("NGOẠI GIAO VÀ THƯƠNG MẠI HOÀNG GIA") to `scenes/ui/hud.tscn`.
   - Wired `scripts/ui/hud.gd` to list external factions, handle diplomatic gift tributes, treaty negotiations, war/peace actions, and visiting caravan quick-trade.
   - Updated `scripts/world/world_view.gd` with daily faction simulations and scheduled caravan arrivals every 5 days starting Day 3.
5. **Automated Test Suite & Evidence:**
   - Authored `scripts/test/test_factions_and_battles.gd` validating TC-6.1 (diplomatic treaties, NAP requirements, gifts, war declarations, atomic buy/sell transactions, stock limits, insufficient fund rejection, zero duplication) and TC-6.2 (100% deterministic reproducibility, superior force victory, plunder mechanics, tier 3 fortification & terrain overcoming raw numerical advantage).
   - Captured runtime screenshots `screenshot_phase6.png` and `screenshot_phase6_diplomacy.png` verifying visual HUD button and interactive Diplomacy panel.

### Validations Performed & Results
- **TC-6.1 Trade Conservation & Diplomatic Treaties:** **PASS** (Treaty prerequisites strictly enforced; gifts boost opinion and deduct gold; atomic transactions conserve currency and items; zero duplication).
- **TC-6.2 Deterministic Battle Resolver & Explanations:** **PASS** (Identical seeds produce 100% identical outcomes; explainable casualty breakdown generated; fortifications allow smaller forces to defend successfully).
- **Full Regression Test Matrix:** TC-0.1, TC-0.2, TC-1.1, TC-1.2, TC-1.3, TC-1.4, TC-2.1, TC-2.2, TC-3.1, TC-3.2, TC-4.1, TC-4.2, TC-4.3, TC-5.1, TC-5.2, TC-5.3, TC-6.1, TC-6.2 all passed with exit code 0.
- **Runtime Visual Inspection:** Screenshots `screenshot_phase6.png` and `screenshot_phase6_diplomacy.png` verified with 0 runtime errors.

### Phase 6 Exit Gate Assessment
- **Status: PASSED.** Faction state machine operational; atomic trade verified without duplication; battle resolver produces explainable deterministic outcomes; scripted tests 100% passed.

### Next Exact Step
- Execute Phase 6 local Git checkpoint.
- Proceed to **Phase 7: Population Growth, Victory, Collapse & Summaries** (Task 7.1: deterministic immigration pacing; 5-day continuous prosperity victory hold; deterministic collapse triggers; world summary screens).







