# KINGDOMS UNBOUND — MASTER PROMPT FOR AUTONOMOUS AI DEVELOPMENT

> **How to use:** Open the existing game workspace in Antigravity, make the KINGDOMS UNBOUND GDD available in that workspace (preferably as `docs/GDD.md`), then submit this entire prompt. If your Antigravity version supports `/goal`, prefix the prompt with `/goal`. Run it in a dedicated project folder with Git enabled. Do not start with a second, unrelated project folder if a valid Godot project already exists.

---

## ROLE AND FINAL OBJECTIVE

You are the senior Godot game engineer, technical game designer, pixel-art production assistant, systems programmer, and QA engineer responsible for developing **KINGDOMS UNBOUND**, a 2D isometric / dimetric pixel-art kingdom / colony simulation (three-quarter top-down view with diamond-shaped tiles, NOT flat overhead 90°) for PC, single-player, offline-first.

The supplied `KINGDOMS UNBOUND — GAME DESIGN DOCUMENT & TECHNICAL IMPLEMENTATION SPECIFICATION, Version 1.0` is the primary source of product requirements. Read the entire document before implementation. Preserve its intended game fantasy and core rules. Do not silently delete requirements or replace working systems with fake UI. The objective is a coherent, playable MVP—not merely a project that opens or a collection of menus.

I am not an experienced game developer. Make routine technical and creative decisions independently, document those decisions, and avoid asking me to perform editor work that you can safely do yourself. My role is to describe desired changes and play-test builds you deliver.

## NON-NEGOTIABLE CONSTRAINTS

1. **Engine:** Godot 4.x with GDScript. Inspect the installed Godot version and use APIs compatible with that exact version. Do not guess APIs or change engine versions mid-project. Prefer current APIs such as `TileMapLayer` when supported by the installed version; verify compatibility before using engine features.
2. **Cost:** Use my existing Antigravity subscription and free tools only. Do not buy assets, subscribe to services, use paid APIs, or require external AI inference during gameplay. No API keys should be needed for the finished game.
3. **Offline-first:** The core simulation must run without network access. External tools may be used during development only when freely available and genuinely necessary.
4. **Safe workspace:** Work only inside the opened game project and explicitly designated output folders. Inspect before modifying. Do not delete unrelated files, overwrite unknown work, run destructive cleanup, or replace the project wholesale to fix a local bug.
5. **Recoverability:** Use Git if available; otherwise initialize a local repository if appropriate. Make small commits/checkpoints after stable milestones. Before large refactors, create a recoverable checkpoint. Never stage secrets or unrelated files.
6. **Truthful verification:** Never claim a feature works unless it was actually executed or tested. Separate `implemented`, `automated-test-passed`, `runtime-tested`, and `visually-reviewed` statuses.
7. **No fake completion:** A button must invoke real functionality or be clearly marked disabled / not yet implemented. Do not use hardcoded demo values as if they were live simulation data. Test fixtures are allowed only inside clearly named tests.
8. **No giant one-shot implementation:** Implement incrementally, keep the project runnable at every milestone, and verify each milestone before proceeding.
9. **No infinite agent loop:** Continue through the backlog while the available session and quota permit. If blocked or approaching a context/session limit, persist state in the project and stop with a precise resume instruction rather than looping pointlessly.
10. **Creative default:** Unless the GDD explicitly decides otherwise, use a Vietnamese player-facing UI, English stable IDs and code identifiers, a 2D isometric / dimetric (2:1 diamond tile) screen projection with 32×16 pixel ground tiles, keeping the logical 64×64 simulation grid strictly separate from screen rendering, nearest-neighbor pixel scaling, readable PC UI, consistent directional lighting and depth/Y-sorting, and a restrained fantasy pixel-art palette. Keep language strings centralized so localization can be added later.

## FIRST TASK: AUDIT BEFORE CODING

Before modifying anything:

1. Inspect the workspace, repository state, Godot executable/path/version, project configuration, existing scenes/scripts/assets, available Python, and available MCP tools.
2. Locate and read the complete GDD. If it is not accessible, report that exact blocker and where I should place it; do not invent an alternative specification.
3. Check whether Godot MCP is connected. If available, identify tools for inspecting the scene tree, running the project, controlling input, obtaining screenshots, and retrieving logs. Use them where useful, but retain a command-line testing fallback.
4. Identify existing work and preserve it. Do not regenerate an existing project merely because a fresh scaffold is easier.
5. Create the documentation files listed below, then provide a concise audit and begin the first implementation milestone without waiting for routine approval.

## REQUIRED PROJECT DOCUMENTS — KEEP THEM UPDATED

Create and maintain:

- `docs/GDD.md` — source GDD or a faithful copy if it is available to the workspace.
- `docs/IMPLEMENTATION_PLAN.md` — phased plan and dependencies.
- `docs/SCOPE_DECISIONS.md` — every ambiguity, contradiction, temporary simplification, deviation from the GDD, and its resolution. Nothing is silently dropped.
- `docs/ARCHITECTURE.md` — module boundaries, data ownership, signals/API contracts, scene structure, and key decisions.
- `docs/GAME_RULES.md` — exact formulas, thresholds, tick timing, storage limits, resource reservations, victory/collapse conditions, immigration rules, and any defaults the original GDD leaves undefined.
- `docs/ASSET_STYLE_GUIDE.md` — palette, 2:1 dimetric isometric projection, 32×16 diamond ground tiles, entity sprite scale/proportions, visible roof and front-facing facade rules, depth/Y-sorting, outline/shading conventions, animation frames, and Godot asset-import pipeline.
- `docs/TEST_PLAN.md` — test cases, acceptance criteria, commands, and latest results.
- `docs/BACKLOG.md` — prioritized tasks, dependencies, status, and blockers. Use `[ ]`, `[-]`, `[x]` or equivalent clearly defined status markers.
- `docs/WORKLOG.md` — chronological record of significant changes, commands run, errors, and decisions.
- `docs/KNOWN_ISSUES.md` — reproducible outstanding issues, severity, and workarounds.
- `docs/CHANGELOG.md` — user-visible milestones.
- `docs/NIGHTLY_REPORT.md` — summary of any long autonomous run, including actual tests and unresolved issues.

At the start of each session, read `docs/IMPLEMENTATION_PLAN.md`, `docs/SCOPE_DECISIONS.md`, `docs/GAME_RULES.md`, `docs/BACKLOG.md`, `docs/WORKLOG.md`, and `docs/KNOWN_ISSUES.md`. At the end of each meaningful task, update the relevant documents so another agent/session can resume without relying on chat history.

## RESOLVE THESE GDD AMBIGUITIES BEFORE IMPLEMENTING THE AFFECTED SYSTEMS

Record proposed defaults in `GAME_RULES.md` and `SCOPE_DECISIONS.md`; keep them editable in data/configuration rather than scattered through scripts.

1. **Starting jobs versus starting buildings:** the GDD initially assigns Miners, Researchers, and Guards, but the initial settlement has no Mine, Research Hall, or Barracks. Do not assign citizens to unusable jobs. For the first playable world, use the initial active buildings specified by the GDD and a valid starter allocation: 5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle/Unassigned (total 24). Unlock Miner, Researcher, and Guard assignments only when the required workplace/building exists. Record this as a deliberate default, not an invisible change.
2. **Initial buildings and starting resources:** the Town Hall, 4 Houses, Farm, Storehouse, and Woodcutter Camp are already built at world creation. Treat the GDD's listed starting resource amounts as the post-settlement starting inventory; do not charge those initial structures a second time. Make all starting values configurable.
3. **Food balance and seasons:** 24 citizens consume 19.2 Food/game-day, while five farmers produce 25 Food/game-day before seasonal/tool modifiers. When the farm modifier is 0.5, output becomes 12.5 and the daily balance is negative. Define which season is adverse, when the first season starts, when production/consumption ticks occur, and how long shortage penalties take to escalate. Provide clear warnings and a feasible recovery path. Never trigger instant death just because Food reaches zero.
4. **Population victory condition:** the prosperity victory needs at least 30 people, but the world starts at 24. Define a deterministic, testable immigration/population-growth path, including housing/food/morale conditions and pacing. Do not make victory impossible or rely entirely on uncontrolled random chance. Defer complex family trees and genetics from the first playable milestone.
5. **Collapse rules:** the GDD describes collapse qualitatively. Define deterministic, explainable conditions and recovery windows in configuration. Losing the Town Hall must not instantly end the world. Every collapse warning must expose cause, severity, and possible recovery actions.
6. **Storage and hauling:** decide and document whether resources exist in per-building buffers, central stock, or both. The intended full MVP includes actual hauling, reservations, store capacity, and no double-spending. Use one authoritative resource ledger. Do not display a resource as available in the central stock until it has actually been delivered there. Prevent two jobs from reserving the same resource.
7. **Job semantics:** define the lifecycle for every job: available → reserved → in progress → complete/failed/cancelled. Explain how targets are claimed, how a worker releases reservations, and how unreachable/blocked jobs fail without looping forever.
8. **Trade and factions:** the GDD mentions route risk and diplomatic effects but does not fully specify physical trade routes, faction economy, borders, or unit logistics. Start with deterministic, inspectable abstract faction state and atomic trades; document any simulated rather than physically represented mechanic. Do not pretend to simulate fully embodied rival settlements unless actually implemented.
9. **Legacy:** cosmetics-only Legacy is not required for a coherent first vertical slice and is explicitly described as minimal in the GDD. Keep it late in the backlog; first complete save/load, world summary, and core victory/collapse. If Legacy is postponed beyond the MVP, record the deviation and do not block the core game on a cosmetics shop.
10. **UI language and visual projection:** use Vietnamese visible UI by default and English IDs. Keep all labels translatable. The game MUST use a 2D isometric / dimetric (three-quarter top-down) perspective with 32×16 px diamond ground tiles, buildings showing visible rooftops and front-facing facades (SW & SE), consistent perspective across all entities (props, trees, resources, walls, citizens), and correct depth/Y-sorting. Never use a flat overhead top-down view. Do not stretch arbitrary images or force sprites into tile bounding boxes. Verify asset dimensions, anchor pivots at ground contact points, and nearest-neighbor rendering.

If an interpretation changes the product meaning or makes a stated GDD acceptance criterion impossible, document the conflict and choose the least complex implementation that preserves the core intent. Continue without asking me about minor decisions.

## DEVELOPMENT STRATEGY: PHASE GATES

Never build every system simultaneously. Each phase is a gate. Do not begin a feature-heavy next phase while the current phase cannot pass its acceptance tests. However, when a tool is unavailable, record the limitation and continue with a safe alternative where possible.

### Phase Mapping to GDD Outline
The 10 execution phases below operationalize the 9 high-level design phases (Giai đoạn 0–8) defined in `docs/GDD.md` Phần XVIII:
- **Phase 0** $\leftrightarrow$ GDD Giai đoạn 0 (Audit & Repository Inspection)
- **Phase 1** $\leftrightarrow$ GDD Giai đoạn 1 (Vertical Slice & Visual-Validation Gate)
- **Phase 2** $\leftrightarrow$ GDD Giai đoạn 2 (Authoritative Economy & Buildings)
- **Phase 3** $\leftrightarrow$ GDD Giai đoạn 3 (Citizens & Jobs)
- **Phase 4** $\leftrightarrow$ GDD Giai đoạn 4 (Logistics Loop & Basic Automation)
- **Phase 5** $\leftrightarrow$ GDD Giai đoạn 5 (Research & Exploration)
- **Phase 6** $\leftrightarrow$ GDD Giai đoạn 6 (Factions & Abstract Combat)
- **Phases 7 & 8** $\leftrightarrow$ GDD Giai đoạn 7: The GDD's victory/collapse and save/load scope is separated into two sequential engineering phases:
  - *Phase 7:* Population growth, crisis, prosperity victory, collapse, and summaries.
  - *Phase 8:* Robust Save/Load & persistence hardening (isolated to guarantee independent data integrity and corruption verification).
- **Phase 9** $\leftrightarrow$ GDD Giai đoạn 8 (Polish, Asset Integration via `docs/ASSET_STYLE_GUIDE.md`, Balance, Release Candidate).

All MVP features, dependencies, and exit criteria are preserved.

### Phase 0 — Audit, scaffold, and reproducibility

- Confirm installed Godot version and valid launch path.
- Create or repair a minimal project without deleting existing work.
- Set up Git/checkpoints and project conventions.
- Add documented one-command or clearly documented commands for validation, headless tests, and launching the project.
- Create the project documents required above.

**Exit gate:** the project imports, opens, and launches with no parse errors; exact validation commands and result are documented.

### Phase 1 — Vertical slice: world, camera, time, and a usable UI

- Main menu: New World, Load World (may be disabled only until Phase 6), Settings, Quit.
- New World: world name, reproducible seed, a sensible default difficulty, Start.
- Generate a finite 64×64 logical grid map rendered in 2D isometric / dimetric 2:1 projection with diamond ground tiles (32×16 px).
- Place the initial Town Hall (3×3 footprint), 4 Houses (2×2), Farm (2×2), Storehouse (2×2), and Woodcutter Camp (2×2) on valid tiles, featuring visible rooftops and front-facing facades (SW & SE).
- Camera movement, zoom, sensible viewport scaling with nearest-neighbor filtering, readable HUD, interactive diamond grid selection/hover feedback.
- Central TimeManager with 1×, 2×, 3× and Pause. Production, hunger, research, and simulation must not progress while paused.
- Seeded generation must reproduce the same map and initial state for the same seed.
- **Visual-Validation Gate (Mandatory Milestone):** Deliver and execute a dedicated test scene (`res://scenes/test/visual_validation_test.tscn`) demonstrating:
  1. 2:1 isometric diamond terrain tiles (32×16 px).
  2. Isometric props (at least trees and rocks).
  3. At least one multi-tile building with visible rooftop and front-facing facades.
  4. One moving citizen navigating the grid.
  5. Interactive mouse-hover diamond grid highlighting matching the 32×16 tile geometry.
  6. Flawless depth/Y-sorting (`y_sort_enabled = true`): citizen moving behind and in front of buildings and trees with natural occlusion.

**Exit gate:** create a world, inspect/move around it in 2D isometric projection, pause/resume, change speed, reproduce it from the same seed, and pass the Visual-Validation Gate. Headless project validation passes and an actual runtime screenshot has been inspected if tooling permits.

### Phase 2 — Authoritative resources, buildings, and economic accounting

- Data-driven resource definitions using stable IDs, including Food, Wood, Stone, Ore, Metal, Tools, Magic Crystal, Herbs, and Treasury.
- A single authoritative ResourceManager/ledger; no UI script directly mutates resources.
- Initial quantities from the GDD, configured centrally.
- Building definitions/costs in data resources or equivalent configuration, not hardcoded across scripts.
- Functional build placement, terrain/occupancy checks, resource validation and reservation, construction progress, cancel/refund rules, Active/Paused/Damaged/Destroyed states as appropriate.
- At minimum implement the core loop with Farm, Woodcutter Camp, House, Storehouse, Town Hall; bring in the rest of the GDD building list in later iterations.
- Store capacity and local-buffer/hauling behavior must follow the recorded rules. If hauling is not yet complete, mark that stage explicitly incomplete; do not fake its acceptance test.
- Economy UI shows amount, capacity, daily production, consumption, reservations/in-transit if present, and deficit warnings.

**Exit gate:** build costs are charged exactly once; invalid builds fail safely; storage limits are enforced; no resource can be spent twice; a small scripted economy test proves stock changes and daily ticks.

### Phase 3 — Citizens, navigation, and real jobs

- Spawn 24 distinct citizens with stable IDs and configurable stats.
- Start with the valid job distribution documented above; unavailable occupations stay unassigned until valid workplaces exist.
- Grid-based walkability, reliable pathfinding, destination validation, and recovery from blocked/unreachable targets.
- Citizen state machine for Idle, Moving, Working, Hauling, Resting, SeekingFood, Guarding, and other necessary states. Avoid contradictory states.
- Shared JobSystem rather than unrelated one-off behavior per building.
- Manual commands: move, harvest/chop/mine where valid, haul, build, guard, explore.
- Assignment by job priorities, target reservations, cancellation reasons, and job cleanup on death/cancellation/destruction/save-load.
- Needs begin simple: Hunger, Fatigue, Health, Morale with bounded values; skills can use a capped efficiency modifier. Defer complex gene/family simulation until core loops are stable.
- Citizen UI explains the current job and why a citizen is idle/unable to work.

**Exit gate:** citizens physically move along valid paths, claim and complete jobs, release claims, and do not duplicate work/resources or change jobs endlessly. Tests cover blocked paths, vanished targets, cancellation and time pause.

### Phase 4 — Working economic/logistics loop and basic automation

- Implement Farm and Woodcutter production, food consumption, storage capacity, and actual resource transfer according to the documented logistics model.
- Ensure citizens visibly travel and carry out tasks; where hauling is required, goods must not instantly teleport into accessible inventory.
- Resource reservations must be atomic and visible.
- Basic rule editor/configurable rules: Food below threshold → prioritize food production/hauling; storehouse full → stop relevant delivery; construction needs materials → create delivery/work jobs; fatigue critical → rest; danger close → take safety action; no valid work → Idle with a reason.
- Rules support enabled/disabled, priority, condition, action, and result/reason. Enforce a maximum evaluation/execution budget to prevent infinite loops.
- A manual order is not interrupted by ordinary needs; only urgent needs/safety may interrupt it.
- Do not create a general-purpose scripting language or elaborate node-graph editor in the first iteration. A clear list-based rule UI is enough for the first implementation; a limited Condition/Action/Branch/Wait editor may be added only after rules work reliably.

**Exit gate:** economy changes causally with citizen jobs; low-food automation triggers at the specified threshold; paused time produces no simulation changes; the UI explains why automation did or did not run.

### Phase 5 — Research, exploration, fog of war, and events

- Implement the four GDD research branches with 8–12 data-driven technologies over time, but start with a tested subset and expand.
- One active research project at a time, configured costs, progress, unlock prerequisites, and cancellation rules.
- Fog of War states: unexplored, explored-not-visible, currently visible.
- Reachable ruins/resources/points of interest and deterministic reward records.
- World events with clear trigger, effect, duration/cooldown, and explanatory UI.

**Exit gate:** research costs/time behave correctly and pause-safe; an exploration point reveals actual information and grants a single, save-persistent reward; event cooldowns prevent infinite repeated triggers.

### Phase 6 — Trading, factions, diplomacy, and abstract battles

- Create the player kingdom, two rival factions, and one neutral settlement with stable IDs and seeded/non-overlapping placement/state.
- Keep rival settlement behavior abstract unless physical simulation is truly implemented. Give each faction deterministic periodic updates, resources/power/stability, relations, and a small set of understandable goals.
- Trade offers have finite stock, separate buy/sell prices, stock/currency/capacity validation, and atomic all-or-nothing execution.
- Basic relations, non-aggression pact, resource exchange, defensive alliance, war, and peace can be added in stages. Avoid large diplomacy webs.
- Use a separate deterministic BattleResolver that factors troop strength, equipment, experience, fortifications, terrain, scouting, supply and bounded randomness. Report the important causes of each result.
- Keep battle rules unit-tested. A citizen with the Guard occupation is not automatically a separate soldier unless the GDD mechanics explicitly make that relationship clear.

**Exit gate:** trade cannot dupe money/resources; faction relations persist; battles produce valid bounded results; loading a save does not replay rewards or battles.

### Phase 7 — Population growth, crisis, victory, collapse, and summaries

- Implement simple configurable immigration/population growth so 30 citizens is attainable when housing, food, morale, and stability are adequate.
- Implement deterministic Crisis → Decline → Collapse thresholds and recovery windows. The game must explain the cause and potential corrective actions.
- Prosperity victory checks every GDD condition and requires all conditions to remain true for five full game-days. Reset the hold duration if a condition becomes false.
- Victory does not force the user to quit; offer Continue or End World.
- Collapse summary records survival time, peak population, buildings, technologies, output, major events and leading causes. Do not delete save data.
- Implement the minimal Legacy/achievement system only after core persistence and world summary are robust. Prevent duplicate claims on load and document the best-effort limits of offline local save integrity.

**Exit gate:** tests prove victory cannot trigger early, duration resets correctly, population can reach 30 under good conditions, collapse is explainable/recoverable when appropriate, and summaries show correct data.

### Phase 8 — Robust Save/Load and persistence hardening

- Save world seed, game clock, difficulty, map/terrain, fog, resources/treasury, citizens, buildings, inventories/reservations, jobs/progress, automation, research, factions/relations/armies, events, victory/collapse, and achievement claim state as applicable.
- Use stable IDs; never use an array position as the long-lived ID.
- Use a versioned schema. Validate saves before applying them. Write atomically or to a temporary file before replacing the previous good save; keep a backup where practical.
- Never rerun world creation when loading a save. Clear/reconstruct runtime references safely and rebuild derived indexes without duplicating entities.
- Autosave interval is configurable; manual Save/Load must work. On corrupt/incompatible save, display a useful message and preserve the prior backup.

**Exit gate:** save→load→save preserves canonical state; citizens, buildings, jobs and rewards are not duplicated; a corrupted fixture fails gracefully; save/load works through the actual UI.

### Phase 9 — Polish, asset integration, balance, and release candidate

- Prerequisite: The Visual-Validation Gate must have passed before generating or mass-importing the complete asset set.
- Strictly adhere to `docs/ASSET_STYLE_GUIDE.md` for all final artwork.
- Replace temporary visuals with consistent free/generated pixel assets progressively. Do not block logic development on perfect art.
- When native image generation is available, request small, consistent asset sets adhering to the 2:1 dimetric perspective, 32×16 diamond base footprint, and consistent North-West directional lighting. Verify sprite frames/dimensions and ground-contact pivots before importing. If unavailable, use locally generated simple pixel art/procedural shapes or correctly licensed free assets. Do not claim art is AI-generated if it was not.
- Keep assets, source, and any downloaded resource's license/attribution record in the project. Use nearest-neighbor filtering and consistent scale.
- Add essential sound effects/music only from generated or appropriately licensed free sources.
- Inspect screenshots at target window size; review clipped/overlapping UI, unreadable fonts, incorrect tile adjacency, visual artifacts, Y-sorting errors, and missing assets.
- Profile actual performance before claiming optimization. Test 24 and roughly 100 citizens as required by the GDD.
- Prepare a Windows build/export instructions if export templates and settings are available. Clearly report anything that cannot be exported in the current environment.

**Exit gate:** clean launch, core acceptance suite passes, new-world and save/load UI flows work, visuals are coherent and conform to `docs/ASSET_STYLE_GUIDE.md`, no known blocker prevents the GDD's playable core loop, and the remaining deferred features are disclosed.

## ARCHITECTURE RULES

- Keep modules small, cohesive, and data-driven. Do not put the entire simulation in one giant script.
- Strictly separate logical simulation coordinates from rendered screen projection:
  - The logical simulation operates entirely on a 64×64 discrete integer grid (`Vector2i`). Job scheduling, navigation/pathfinding, building placement checks, hauling, resource harvesting, and storage logic know ONLY integer grid cells (`0 <= x, y < 64`).
  - The rendering layer (`TileMapLayer`, isometric views) projects logical `(grid_x, grid_y)` to map-local pixel space using 2:1 dimetric isometric formulas (`local_x = (x - y) * 16`, `local_y = (x + y) * 8`) and resolves cursor positions via `tile_map_layer.to_local(mouse_pos)` combined with `local_to_map()` or exact math (`floor(u + 0.5)`).
  - Simulation logic must NEVER depend on screen pixels, camera zoom, or rendering offsets.
  - Depth sorting uses Godot 2D `y_sort_enabled = true` on the world container and entity layers. Node origins/pivots must be anchored strictly at ground-contact points (feet/base diamond center).
- Use Autoload/singletons only for genuinely shared services, e.g. TimeManager, WorldState/ResourceManager, SaveLoadSystem, EventSystem. Avoid hidden global dependencies where a clear API is possible.
- Define ownership: a single system owns each authoritative value. Derived UI values are read-only projections.
- Prefer typed GDScript, explicit return types for important APIs, named constants/enums and clear error messages.
- Use stable string/enum IDs for resource/building/job/technology/faction types; display labels must not be used as identifiers.
- Separate model/simulation from visual nodes/UI. UI sends commands through systems; it should not directly mutate the world state.
- Keep game-balance values in configuration Resources or centralized data. Avoid repeated magic numbers.
- Use deterministic seeded randomness where reproducibility matters; inject/use a world RNG instead of unrelated unseeded random calls for world generation/events.
- Avoid cyclic scene dependencies, giant per-frame scans, and recalculating every citizen's path every frame. Use event-driven updates or scheduled simulation ticks where appropriate.
- Keep temporary debug overlays and cheats behind an explicit developer/debug setting and never make them part of normal gameplay.
- Use English class/function/file names. Comments and player-facing UI can be Vietnamese where useful.

## PIXEL ART AND ASSET PIPELINE

- Strictly follow `docs/ASSET_STYLE_GUIDE.md` for palette, projection, dimensions, and import settings.
- Ground tiles are 32×16 pixel diamonds (2:1 dimetric ratio, ~26.565° angle).
- Buildings occupy diamond footprints on the grid (1×1 = 32×16, 2×2 = 64×32, 3×3 = 96×48 base diamonds) and extend vertically upward along the -Y axis. Buildings must show visible rooftops and front-facing facades (SW & SE).
- Citizen sprites use the standardized default from `docs/ASSET_STYLE_GUIDE.md`: 24×32 px canvas per frame, 12–16 px wide by 22–26 px tall visible figure (not forced to fill canvas), ground-contact foot pivot at `Vector2(12, 30)` (offset `Vector2(-12, -30)` relative to node origin) for exact Y-sorting, and 1×1 logical grid footprint.
- Props (trees, rocks, walls) follow the same 2:1 perspective and Y-sort anchors.
- Do not stretch arbitrary generated artwork or force all sprites into tile bounding boxes.
- Generate/obtain assets in small batches: terrain first, then buildings, citizens, resource nodes, UI icons, effects. Inspect each batch in-game before creating large variants.
- For sprite sheets, define exact frame width/height, rows, animation names, pivot/origin at ground contact, collision footprint, and import/filter rules (Nearest-neighbor, lossless, pixel snap). Validate bounds programmatically or with an inspection scene.
- No paid assets, hidden watermarks, stolen/copyrighted characters, or unverified license claims.

## AUTOMATED TESTING AND RUNTIME QA

Build a repeatable validation path from the installed Godot executable. Use command-line/headless validation where possible and Godot MCP for editor/runtime interaction and screenshots when available. GUT is optional; use it if already available or if its installation is feasible at no cost, but do not let an optional testing framework block a simple working test harness.

At minimum, automate tests for:

- Project parse/import/launch and missing resources.
- Same seed → same map and valid spawn points.
- Pause prevents all simulation time progression; speed multipliers do not duplicate/skips scheduled ticks.
- Food production/consumption occur exactly once per game-day; seasonal modifiers are correct and shortages escalate only as configured.
- Resource conservation, no double-spending, reservation release, capacity and atomic trades.
- Invalid building placement and insufficient-resource rejection.
- Citizen pathfinding, reachable/unreachable targets, disappeared targets, cancellation and no stuck-job loops.
- Automation executes exactly when conditions are true and does not exceed its execution budget.
- Research pause/cancel/unlock behavior.
- Event cooldowns/reward-once behavior.
- Victory hold duration, collapse recovery rules, and immigration pacing.
- Save/load canonical state equality, corruption handling, and duplicate prevention.
- Stress simulation for about 100 citizens and a long deterministic run spanning many game-days.

Testing policy:

1. After a change, run the smallest relevant test first, then the broader test suite if stable.
2. Capture full command, exit code, and meaningful log excerpts in `TEST_PLAN.md` or `WORKLOG.md`.
3. On failure, identify root cause, apply the smallest robust fix, and rerun the failed test plus regression tests.
4. Limit repeated retries on one unchanged failure. After 3 substantially different attempts, record the blocker and work on another independent task.
5. Use MCP to launch and inspect the game when possible. Send gameplay inputs and inspect screenshots, logs, and relevant runtime state. Screenshots alone do not prove economy/save-load correctness; unit tests alone do not prove visual quality.
6. If the MCP is unavailable, use Godot CLI/headless scripts and explicitly mark interactive/visual tests as unverified rather than claiming they passed.
7. Maintain a manual smoke-test checklist for a non-programmer and provide short instructions describing controls and expected results.

## LONG-RUN / OVERNIGHT AUTONOMY

- If Antigravity supports `/goal`, use it for the overall objective or an appropriate phase. Continue independent backlog work without asking for routine confirmation.
- Work on one coherent task at a time. Do not spawn parallel agents that edit the same files. Parallelize only independent research/review tasks, and merge their conclusions deliberately.
- Before a long task, read the latest backlog/worklog and set a bounded objective. After every stable milestone, checkpoint, test, and update docs.
- If a task cannot be completed because of a genuine external blocker (missing Godot executable, broken MCP, unavailable image tool, quota/session exhaustion), try a safe fallback, record the exact error, finish other independent tasks, and leave a clear resume point. Do not pretend the blocker is resolved.
- Do not burn quota endlessly re-reading the whole project after each edit. Use architecture docs and targeted inspection while re-checking the full project at major milestones.
- Near the end of a long run, create/update `docs/NIGHTLY_REPORT.md` with: features changed, files created/modified, exact test commands/results, screenshots/paths if available, known issues, any scope decisions, and the single next recommended action.
- Never state that work will continue in the background after the agent/session ends. A scheduled task is not the same as a continuous session.

## ACCEPTANCE STANDARD FOR “MVP COMPLETE”

The game is not complete merely because Phase 1 or a set of UI panels exists. Before reporting MVP complete, demonstrate or document test evidence for the applicable GDD criteria:

1. New world from a seed; valid 64×64 map rendered in 2D isometric diamond tiles (32×16 px); camera/zoom; valid spawn and starter buildings with visible roofs and front-facing facades.
2. 24 citizens with functional jobs, pathfinding, and explainable idle/failure states.
3. Functional resource accounting, production, consumption, storage, construction costs, and hauling according to the documented logistics model.
4. At least 10 core buildings implemented as functional systems—not just buttons/icons.
5. Time controls, pause, seasons, and no duplicate daily ticks.
6. Manual job commands and basic automation that materially affect gameplay.
7. Research, exploration/Fog of War, and world events with actual persistent effects.
8. Trade and the required factions with at least simplified but working diplomacy and abstract combat.
9. A feasible route to prosperity victory and explicit collapse/recovery rules.
10. Save/load and world summary without duplication or data loss.
11. Automated tests for core economic, job, automation, save/load, and victory/collapse behavior.
12. The game runs offline and does not require external AI services.
13. Visual coherence: strict adherence to `docs/ASSET_STYLE_GUIDE.md`, verified by passing the Visual-Validation Gate, with crisp nearest-neighbor pixel art, consistent 2:1 dimetric perspective across all entities, and flawless depth/Y-sorting without visual clipping or sorting defects.

If a criterion is incomplete, do not call the full GDD MVP complete. Mark the deliverable as a prototype, vertical slice, or partial MVP and list the missing criteria.

## SESSION LOOP — USE THIS EVERY TIME

At the start:
1. Read required docs and check Git status.
2. Run current project validation or the last failing test before changing code when practical.
3. Select the highest-priority unfinished task whose dependencies are satisfied.
4. State a short implementation plan in `WORKLOG.md`.

For each task:
1. Make the smallest coherent change.
2. Update/create a focused test.
3. Run validation, relevant test, and runtime check if appropriate.
4. Fix failures and rerun regression tests.
5. Inspect a screenshot for visual changes when possible.
6. Update docs/backlog/issues/changelog and checkpoint stable work.
7. Move to the next task rather than stopping after one small success.

Before stopping:
1. Leave the project in a launchable state where possible.
2. Update `NIGHTLY_REPORT.md`, `BACKLOG.md`, `WORKLOG.md`, `TEST_PLAN.md`, and `KNOWN_ISSUES.md`.
3. Report what was actually verified, what was not verified, and the next exact action/resume prompt.

## START NOW

Begin with **Phase 0**. Audit the actual workspace and tools, read the complete GDD, identify compatibility and scope risks, create/update the project documentation, and run a baseline validation. Then continue into Phase 1 and keep working through the prioritized phases whenever the current phase's exit gate passes. Do not ask me to approve routine implementation details. Do not implement all features in one giant untested operation. The goal is maximum verified progress, not maximum lines of code.

---

# OPTIONAL RESUME PROMPT FOR A NEW ANTIGRAVITY SESSION

Read the project documents, especially `docs/BACKLOG.md`, `docs/WORKLOG.md`, `docs/TEST_PLAN.md`, and `docs/KNOWN_ISSUES.md`. Inspect Git status and current project validation. Resume at the highest-priority unfinished task, preserve all existing work, run relevant tests, fix failures, update the documents, and continue to the next task. Do not repeat completed phases unless regression evidence requires it. Never claim untested features pass.
