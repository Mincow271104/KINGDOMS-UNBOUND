# Wildlife Natural Movement — Read-Only Regression Audit

**Date:** 2026-11-15
**Auditor:** Antigravity (Read-Only Audit)
**Target Implementation Report:** `docs/reports/WILDLIFE_NATURAL_MOVEMENT_IMPLEMENTATION_REPORT.md`
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`
**Audit Scope:** Read-only code and regression audit of the Wildlife Natural Movement enhancement across all six Phase 6 species (`bird`, `frog`, `rabbit`, `deer`, `wild_boar`, `mountain_goat`). No production, test, scene, asset, or configuration files were modified.

---

## 1. Audit Scope and Objectives

This audit verifies whether the Wildlife Natural Movement enhancement in:
- `scripts/world/wildlife_config.gd`
- `scripts/world/wildlife_manager.gd`
- `scripts/world/wildlife_actor.gd`
- `scripts/test/test_wildlife_natural_movement.gd`

preserves original Phase 6–8 gameplay behaviors (species behaviors, habitat/walkability constraints, Fog of War, hunting, cookhouse integration, Save/Load, and Phase 9 Monster isolation) without introducing regressions or edge-case defects, with highest priority on **Bird flight/perching preservation**.

---

## 2. Git Branch and Working-Tree Status

- **Current branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Recent HEAD commits (`git log -n 5 --oneline`):**
  - `fa09df2` `test(acceptance): verify integrated campaigns A, B, and C with full GUI runner`
  - `ca61815` `fix(legacy): harden cross-file victory settlement crash recovery and add interruption test coverage`
  - `e32b8c1` `test(legacy): expand meta-progression test suite to 22 scenarios and verify reward lifecycle`
  - `c84df5d` `feat(legacy): implement persistent starting perks, world modifiers, and campaign meta-progression`
  - `4e68d30` `fix(crisis): harden crisis lifecycle transitions, blizzard farming cutoff, and raid persistence`
- **Wildlife files in Git (`git log --all --oneline -- "scripts/world/wildlife*" "scripts/test/test_wildlife*"`):**
  - Returned **no commits**. All wildlife source and test files are currently untracked (`??`) in the working tree:
    - `?? scripts/world/wildlife_actor.gd` (`.uid`)
    - `?? scripts/world/wildlife_config.gd` (`.uid`)
    - `?? scripts/world/wildlife_manager.gd` (`.uid`)
    - `?? scripts/test/test_wildlife_ecosystem.gd` (`.uid`)
    - `?? scripts/test/test_wildlife_natural_movement.gd` (`.uid`)
- The broader working tree also contains unrelated modified (`M`) and untracked (`??`) files from prior project phases (Phase 1–9, Package 3A/3B/4A/4B, assets, and reports), all left completely untouched.

---

## 3. Original vs. Current Behavior (Git History & Project Artifact Comparison)

- **Git history limitation:** Because `scripts/world/wildlife_*.gd` and `scripts/test/test_wildlife_ecosystem.gd` have never been committed to Git, a direct `git diff` against a pre-enhancement commit is **not available**.
- **Phase 6 baseline artifact evidence:** The original Phase 6 implementation is documented in the session artifact `KU_WORLD_EXPANSION_PHASE_6_REPORT.md` (Section 2–5):
  - **Original gameplay behavior:** All 6 species (`bird`, `frog`, `rabbit`, `deer`, `wild_boar`, `mountain_goat`) were managed by `WildlifeManager` using `nav.is_cell_walkable()`, allowed-biome filtering, non-blocking movement (no `world_data.occupancy` writes), `IDLE <-> WANDERING` for `AMBIENT` (`bird`, `frog`), `FLEEING` on threat for `PASSIVE_HUNTABLE` (`rabbit`, `deer`), and `DEFENSIVE_DISPLAY` (1.1s warning) -> `FLEEING` for `DEFENSIVE` (`wild_boar`, `mountain_goat`).
  - **Newly introduced movement & visual behavior:** Species-specific `GaitType`, multi-step `burst_min..burst_max`, `prev_cell` anti-oscillation, `last_dir` + `turn_persistence` heading continuity, `wander_radius` soft tether, `speed_jitter` / `anim_phase` desynchronization, final-step `smoothstep`, isometric screen-X `_apply_step_facing()` with `turn_blend`, and `WildlifeActor.sync_visual()` vertical gait arcs + `IDLE` breathing/bobbing.

---

## 4. Bird Flight / Perching Preservation Investigation (Highest Priority)

### Evidence Examined
1. **`docs/GDD.md`:** Search for `bird`, `wildlife`, `perch`, `fly`, `flight` returned 0 matches; no aerial/perching mechanics are specified in the GDD.
2. **Phase 6 Baseline Artifact (`KU_WORLD_EXPANSION_PHASE_6_REPORT.md`, §3 & §5):** Documents `bird` ("Small Bird") as `Category.AMBIENT` in `GRASSLAND`, `TEMPERATE_FOREST`, `PINE_FOREST` using `IDLE <-> WANDERING` within habitat, with no mention of flight, perching, landing, takeoff, or flying over water/unwalkable tiles.
3. **Current `scripts/world/wildlife_config.gd:42-70`:** Defines `"bird"` with `category = Category.AMBIENT`, `gait_type = GaitType.FLUTTER`, `burst_min = 2`, `burst_max = 5`, `turn_persistence = 0.70`, `wander_radius = 10`, `hop_height = 5.0`, `idle_bob_amp = 0.6`, `idle_bob_freq = 3.2`.
4. **Current `scripts/world/wildlife_manager.gd:351-405` (`_pick_wander_cell`):** Processes `"bird"` through the exact same ground-based loop as every other species: `CARDINAL_DIRS`, `nav.is_cell_walkable(nb)`, `IsoMath.grid_distance(nb, world_data.center_spawn) <= 4`, `WildlifeConfig.is_biome_allowed()`, `prev_cell` exclusion, `wander_radius` tether, and `turn_persistence`.
5. **Current `scripts/world/wildlife_actor.gd:51-52` (`sync_visual`):** `GaitType.FLUTTER` applies `y_off -= sin(t * PI) * hop_h + absf(sin(t * PI * 3.0)) * 1.2` to `_sprite.offset.y` while `is_moving == true`.

### Required Classification & Findings
- **Classification:** **Cannot determine from available source/history** (via Git commit diff, because `scripts/world/wildlife_*.gd` are untracked in Git); however, **per Phase 6 baseline documentation (`KU_WORLD_EXPANSION_PHASE_6_REPORT.md`) and current source code, Bird never had an aerial/perching state machine and continues to use ground-based `nav.is_cell_walkable()` movement with `GaitType.FLUTTER` as a visual-only vertical sprite animation.**
- **Answers to Audit Questions 2A.1–2A.7:**
  1. No evidence of prior flight, perching, landing, or takeoff behavior exists in `docs/GDD.md`, `KU_WORLD_EXPANSION_PHASE_6_REPORT.md`, or `WildlifeConfig.BehaviorState`.
  2. N/A (no prior aerial/perching state machine was found).
  3. **Yes:** `bird` is processed through the exact same `advance_simulation()` and `_pick_wander_cell()` ground logic as all other species (`wildlife_manager.gd:254-405`).
  4. `nav.is_cell_walkable()`, `CARDINAL_DIRS`, `prev_cell`, `wander_radius = 10`, and `is_biome_allowed()` restrict `bird` to walkable ground cells in `GRASSLAND`, `TEMPERATE_FOREST`, and `PINE_FOREST` (it cannot fly over water, cliffs, or buildings).
  5. `GaitType.FLUTTER` is **only** a vertical `Sprite2D.offset.y` oscillation in `WildlifeActor.sync_visual()` (`wildlife_actor.gd:51-52`) while the logical animal steps between walkable ground cells.
  6. Logical cell updates (`rec["cell"]`) remain cleanly separated from visual interpolation (`actor.sync_visual()`).
  7. **Yes:** Visually `bird` bobs/flutters upward (`hop_height = 5.0` + 3-cycle flutter), appearing airborne during movement while logically constrained to ground navigation (`nav.is_cell_walkable()`).

---

## 5. Six-Species Behavioral Assessment

### Bird (`bird` — `Category.AMBIENT`)
- **Original gameplay behavior:** Ambient `IDLE <-> WANDERING` in `GRASSLAND`, `TEMPERATE_FOREST`, `PINE_FOREST`; `awareness_radius = 0`, non-huntable.
- **New movement behavior:** `burst_min..max = 2..5`, `turn_persistence = 0.70`, `wander_radius = 10`, `speed_jitter` (`0.88..1.12`), `prev_cell` anti-oscillation.
- **New visual animation:** `GaitType.FLUTTER` (`hop_height = 5.0`), `idle_bob_amp = 0.6`, `idle_bob_freq = 3.2`, `turn_blend` smoothing.
- **Confirmed preserved:** Ambient `IDLE <-> WANDERING`, biome/walkable constraints, no hunting/threat reaction.
- **Potential regression / missing evidence:** **Defect D-01** (below) affects `bird` if saved while `WANDERING` (since `awareness_radius = 0`, a frozen loaded bird never gets unstuck via threat scan). Visual flight appearance remains logically ground-constrained.

### Frog (`frog` — `Category.AMBIENT`)
- **Original gameplay behavior:** Ambient `IDLE <-> WANDERING` strictly in `WETLANDS`; `awareness_radius = 0`, non-huntable.
- **New movement behavior:** `burst_min..max = 1..2`, `idle_min..max = 2.4..5.6`, `turn_persistence = 0.45`, `wander_radius = 5`.
- **New visual animation:** `GaitType.HOP` (`hop_height = 4.0`, squash/stretch `sy = 1.0 + arc * 0.12`), `idle_bob_amp = 0.5`, `idle_bob_freq = 1.8`.
- **Confirmed preserved:** Wetland-only habitat restriction, `nav.is_cell_walkable()` enforcement, short bursts and longer idle pauses.
- **Potential regression / missing evidence:** **Defect D-01** (below) permanently freezes a `frog` saved mid-`WANDERING` (`awareness_radius = 0`).

### Rabbit (`rabbit` — `Category.PASSIVE_HUNTABLE`)
- **Original gameplay behavior:** `GRASSLAND`, `TEMPERATE_FOREST`; flees (`FLEEING`) on threat within `awareness_radius = 4`; huntable (`raw_meat_yield = 2`, `recovery_hours = 48.0`).
- **New movement behavior:** `burst_min..max = 2..4`, `idle_min..max = 1.8..4.2`, `turn_persistence = 0.55`, `wander_radius = 7`, `move_speed = 2.3`, `flee_speed = 3.6`.
- **New visual animation:** `GaitType.HOP` (`hop_height = 3.5`, vertical stretch), `idle_bob_amp = 0.7`, `idle_bob_freq = 3.6`.
- **Confirmed preserved:** Fleeing from citizens/player units (`wildlife_manager.gd:240-243`, `304-318`), hunting reservation/completion (`wildlife_manager.gd:581-615`), `BEING_HUNTED` freeze.
- **Potential regression / missing evidence:** **Defect D-01** (below) freezes a `rabbit` saved mid-`WANDERING` until a threat enters `awareness_radius = 4` or a hunter reserves/hunts it.

### Deer (`deer` — `Category.PASSIVE_HUNTABLE`)
- **Original gameplay behavior:** `GRASSLAND`, `TEMPERATE_FOREST`, `PINE_FOREST`; flees on threat within `awareness_radius = 5`; huntable (`raw_meat_yield = 4`, `recovery_hours = 72.0`).
- **New movement behavior:** `burst_min..max = 3..6`, `idle_min..max = 2.8..6.2`, `turn_persistence = 0.80`, `wander_radius = 9`, `move_speed = 2.0`, `flee_speed = 3.5`.
- **New visual animation:** `GaitType.WALK` (`hop_height = 1.2`), `idle_bob_amp = 0.4`, `idle_bob_freq = 1.5`.
- **Confirmed preserved:** Longer pauses, smoother directional continuity (`0.80`), fleeing, and hunting lifecycle.
- **Potential regression / missing evidence:** **Defect D-01** (below) freezes a `deer` saved mid-`WANDERING` until a threat/hunter interacts with it.

### Wild Boar (`wild_boar` — `Category.DEFENSIVE`)
- **Original gameplay behavior:** `TEMPERATE_FOREST`, `WETLANDS`; enters `DEFENSIVE_DISPLAY` (`warning_duration = 1.1s`) when approached within `awareness_radius = 4`, then retreats (`FLEEING`) without attacking; non-huntable.
- **New movement behavior:** `burst_min..max = 2..4`, `idle_min..max = 2.4..5.0`, `turn_persistence = 0.60`, `wander_radius = 7`, `move_speed = 1.8`, `flee_speed = 2.8`.
- **New visual animation:** `GaitType.TROT` (`hop_height = 1.5`), `idle_bob_amp = 0.8`, `idle_bob_freq = 2.8`, warm tint + warning badge in `DEFENSIVE_DISPLAY`.
- **Confirmed preserved:** `DEFENSIVE_DISPLAY` -> `FLEEING` non-attacking retreat (`wildlife_manager.gd:244-250`, `299-303`), non-huntable status.
- **Potential regression / missing evidence:** **Defect D-01** (below) if saved mid-`WANDERING`.

### Mountain Goat (`mountain_goat` — `Category.DEFENSIVE`)
- **Original gameplay behavior:** `HIGHLANDS` only; `DEFENSIVE_DISPLAY` (`1.1s`) -> `FLEEING` when approached within `awareness_radius = 4`; non-huntable.
- **New movement behavior:** `burst_min..max = 2..4`, `idle_min..max = 2.4..5.0`, `turn_persistence = 0.65`, `wander_radius = 6`, `move_speed = 1.9`, `flee_speed = 2.9`.
- **New visual animation:** `GaitType.WALK` (`hop_height = 2.2`), `idle_bob_amp = 0.5`, `idle_bob_freq = 2.0`.
- **Confirmed preserved:** Highlands-only biome constraint, `nav.is_cell_walkable()`, `DEFENSIVE_DISPLAY` -> `FLEEING`.
- **Potential regression / missing evidence:** **Defect D-01** (below) if saved mid-`WANDERING`.

---

## 6. Shared-System Regression Assessment

| Shared System | Assessment | Code Evidence |
| :--- | :--- | :--- |
| **Navigation & logical grid** | **Preserved** | `rec["cell"]` updates only when `move_progress >= 1.0` (`wildlife_manager.gd:259-262`); all destinations validated with `nav.is_cell_walkable()`. |
| **Occupancy & collision** | **Preserved** | Wildlife never writes to `world_data.occupancy` and uses `0` A* calls in `advance_simulation()`. |
| **Fog of War** | **Preserved** | `refresh_visibility()` (`wildlife_manager.gd:425-432`) and `inspect_cell()` (`434-440`) read authoritative `rec["cell"]`, not `actor.position`. |
| **Hunting, fleeing, death** | **Preserved** | `BEING_HUNTED` short-circuits `advance_simulation()` (`217-223`) and freezes `WildlifeActor` without bobbing; `complete_hunt()` (`581-615`) erases and `queue_free()`s the actor. |
| **Spawn & population caps** | **Preserved** | `MAX_TOTAL_POPULATION = 70` and per-species `max_pop` unchanged in `wildlife_config.gd`. |
| **Save / Load** | **DEFECT FOUND (D-01)** | `serialize()` (`753-775`) saves `WANDERING` (`1`) and `FLEEING` (`2`), but `deserialize_or_init()` (`777-814`) resets `target_cell = cell` without handling `WANDERING` at cell center (`281-319`). |
| **Deterministic RNG & world gen** | **Preserved** | `generate_initial_population()` seeds from `world_data.seed_value ^ WILDLIFE_RNG_SALT`; `WorldGenerator` terrain/biomes/props untouched. |
| **Phase 6 / 7 / 8 (Hunter & Cookhouse)** | **Preserved** | `test_wildlife_ecosystem.gd` (36/36), `test_hunter_closure.gd` (1076/1076), `test_cookhouse_closure.gd` (33/33) passed in implementation run. |
| **Monster Movement (Phase 9)** | **Preserved** | Zero `monster_*` files modified. |

---

## 7. Movement Logic and Edge-Case Findings

- **`prev_cell` anti-oscillation (`wildlife_manager.gd:376-380`):** Excludes `prev_cell` when other biome-matched neighbors exist; safely falls back to `biome_matches` in dead-ends so animals do not get stuck.
- **`last_dir` & `turn_persistence` (`398-401`):** Only picks `c + last_dir` if it is already in the filtered `pool` (valid walkable, biome-allowed, non-backtrack, within tether). Cannot force an animal into invalid terrain.
- **`wander_radius` soft tether (`382-396`):** Keeps wandering within `wander_radius` of `home_cell` and steers back toward `home_cell` if displaced (e.g., after `FLEEING`).
- **`burst_remaining` (`263-278`, `286-298`):** Cleanly decrements per step and transitions to `IDLE` at `0` or when blocked.
- **`speed_jitter` & `anim_phase` (`160-161`, `257`, `338`):** Desynchronizes step cadence and idle bobbing across animals.
- **Final-step `smoothstep` (`330-331`):** Applied only to visual `t_vis` when `is_moving`, `burst_remaining <= 1`, and `state == WANDERING`; logical `move_progress` remains linear.
- **`turn_blend` & `_apply_step_facing` (`252`, `342-349`, `wildlife_actor.gd:63-64`):** Recovers to `1.0` at `sim_dt * 7.0`; `sync_visual()` clamps `turn_blend` to `[0, 1]`.
- **Save/Load `WANDERING` / `FLEEING` Edge Case (Confirmed Defect D-01):** See Section 9 below.

---

## 8. Tests Actually Executed and Exact Results

No new tests were run during this read-only audit. The following results are verbatim from the implementation run (`docs/reports/WILDLIFE_NATURAL_MOVEMENT_IMPLEMENTATION_REPORT.md`, §4) executed headless (`--headless`) with isolated `APPDATA` (`$env:TEMP\ku_test_appdata_wl`):

- `test_wildlife_natural_movement.gd`: **64 passed, 0 failed**
- `test_wildlife_ecosystem.gd`: **36 passed, 0 failed**
- `test_hunter_closure.gd`: **1076 passed, 0 failed**
- `test_cookhouse_closure.gd`: **33 passed, 0 failed**
- `test_save_load.gd`: **182 passed, 0 failed**
- `test_fog_of_war_reconnaissance.gd`: **127 passed, 0 failed**

*(Graphical D3D12 visual inspection was NOT performed.)*

---

## 9. Confirmed Defects, Potential Risks, and Missing Evidence

### Confirmed Defect D-01 — Save/Load Freezes Animals Saved in `WANDERING` State (and Drops `threat_cell` for `FLEEING`)
- **Severity:** **High**
- **Affected species / system:** All 6 wildlife species (`bird`, `frog`, `rabbit`, `deer`, `wild_boar`, `mountain_goat`) via Save/Load.
- **Exact file and functions:**
  - `scripts/world/wildlife_manager.gd:753-775` (`serialize()`)
  - `scripts/world/wildlife_manager.gd:777-814` (`deserialize_or_init()`)
  - `scripts/world/wildlife_manager.gd:255-319` (`advance_simulation()`)
- **Technical explanation:**
  `serialize()` only normalizes `BEING_HUNTED` to `IDLE` (`lines 759-760`), so animals currently in `WANDERING` (`1`) are saved with `"state": 1`. On load, `deserialize_or_init()` calls `_make_animal_record(..., st_val)` (`line 809`), which initializes `target_cell = cell` and `move_progress = 0.0`. In `advance_simulation()`, the movement step (`line 255`: `if rec["target_cell"] != rec["cell"]`) is skipped, and the at-cell-center state machine (`lines 281-319`) only handles `IDLE`, `ALERT`, `DEFENSIVE_DISPLAY`, and `FLEEING`. Because there is **no** `WANDERING` branch when `target_cell == cell`, any animal loaded with `state == WANDERING` remains permanently stationary in `WANDERING` (`bird` and `frog` forever since `awareness_radius == 0`; others until a threat or hunter interacts with them). Additionally, `FLEEING` (`2`) is saved without `threat_cell`, so a loaded `FLEEING` animal flees with `threat_cell = Vector2i(-1, -1)` until its timer expires.
- **Reproduction scenario:** Run `WildlifeManager.advance_simulation()` until at least one `bird` or `frog` enters `WANDERING`, call `serialize()`, load into a new `WildlifeManager` via `deserialize_or_init()`, and step `advance_simulation()` for any duration with no threats: the loaded `bird`/`frog` stays at `target_cell == cell` in `state == WANDERING` indefinitely.
- **Recommended correction (not implemented):** In `serialize()` and/or `deserialize_or_init()`, normalize `WANDERING` and `FLEEING` (alongside `BEING_HUNTED`) to `IDLE` when `target_cell`/`threat_cell` are not persisted, **or** add a `WANDERING` handler in `advance_simulation()` when `target_cell == cell` to transition to `IDLE` or pick a next wander cell.

### Potential Risks
- **R-01 (Low):** In `wildlife_manager.gd:241-250`, entering `FLEEING` or `DEFENSIVE_DISPLAY` mid-step does not explicitly zero `burst_remaining` (harmless today because `IDLE -> WANDERING` overwrites `burst_remaining` at line 288, but worth keeping clean).

### Missing / Unverified Evidence
- **M-01:** Live D3D12 graphical viewport verification has **not** been executed; visual smoothness of `FLUTTER`, `HOP`, `WALK`, `TROT`, and `turn_blend` is only inferred from headless property assertions.
- **M-02:** Pre-enhancement `wildlife_*.gd` source is absent from Git commit history because the files are untracked.

---

## 10. Overall Audit Verdict

**FAIL** *(due to Confirmed Defect **D-01**: animals saved while `WANDERING` become permanently stuck at `target_cell == cell` after `deserialize_or_init()`, affecting all 6 species—especially `bird` and `frog` which have `awareness_radius == 0`)*.

---

## 11. Read-Only Confirmation

Explicitly confirmed: **No** production code, test files, scenes, assets, or configuration files were modified during this audit. Only this audit report (`docs/reports/WILDLIFE_NATURAL_MOVEMENT_READ_ONLY_AUDIT.md`) was created.
