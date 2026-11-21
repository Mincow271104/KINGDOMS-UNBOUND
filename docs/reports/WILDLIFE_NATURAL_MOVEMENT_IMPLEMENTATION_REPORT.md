# Wildlife Natural Movement — Implementation Report

**Date:** 2026-11-15
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`
**Scope:** Phase 6 Wildlife Ecosystem (`bird`, `frog`, `rabbit`, `deer`, `wild_boar`, `mountain_goat`)

---

## 1. Implementation Overview

### Original Problems Identified
1. **Mechanical 1-cell stop-and-go loop:** Every wander step immediately transitioned back to `IDLE`, causing animals to move like chess pieces one tile at a time.
2. **Ping-pong oscillation:** `_pick_wander_cell()` had no memory of `prev_cell` or `last_dir`, allowing animals to repeatedly step back and forth between two adjacent cells.
3. **Abrupt facing snaps:** Facing used `(next_cell.x - cell.x) < 0` in grid space rather than isometric screen-X projection and snapped `flip_h` instantaneously without turn smoothing.
4. **Uniform behavior across species:** All six species shared identical movement presentation regardless of whether they were birds, frogs, rabbits, deer, wild boars, or mountain goats.
5. **Static sprite presentation:** `WildlifeActor.sync_visual()` positioned sprites at interpolated coordinates without gait arcs (hop, flutter, walk/trot) or idle breathing/bobbing.

### Improvements Implemented
- Added species-specific gait types (`FLUTTER`, `HOP`, `WALK`, `TROT`), multi-step movement bursts (`burst_min`..`burst_max`), `turn_persistence`, `wander_radius` soft tethering, `hop_height`, and idle bobbing (`idle_bob_amp`, `idle_bob_freq`).
- Added `prev_cell` anti-oscillation filtering, `last_dir` directional persistence, per-animal `speed_jitter` (`0.88..1.12`) and `anim_phase` (`0..TAU`) desynchronization, smoothstep deceleration on final burst steps, and screen-X-projected `_apply_step_facing()` with `turn_blend` smoothing.
- Extended `WildlifeActor.sync_visual()` with gait-specific vertical arcs, squash/stretch on `HOP`, `IDLE`-only breathing/bobbing (disabled during `BEING_HUNTED`), and horizontal turn-blend scaling.

### Species Covered
- `bird` (Small Bird — `AMBIENT`)
- `frog` (Frog — `AMBIENT`)
- `rabbit` (Rabbit — `PASSIVE_HUNTABLE`)
- `deer` (Deer — `PASSIVE_HUNTABLE`)
- `wild_boar` (Wild Boar — `DEFENSIVE`)
- `mountain_goat` (Mountain Goat — `DEFENSIVE`)

---

## 2. Files Changed

| File | Status | Purpose |
| :--- | :--- | :--- |
| `scripts/world/wildlife_config.gd` | Untracked (`??`) | Added `GaitType` enum and per-species gait, burst, turn persistence, wander radius, hop height, and idle bobbing parameters; tuned `frog` and `deer` idle durations. |
| `scripts/world/wildlife_manager.gd` | Untracked (`??`) | Added multi-step burst state transitions, `prev_cell` anti-oscillation, `wander_radius` soft tether, `turn_persistence` heading bias, per-animal `speed_jitter`/`anim_phase`, screen-X `_apply_step_facing()` with `turn_blend`, and extended `sync_visual()` calls. |
| `scripts/world/wildlife_actor.gd` | Untracked (`??`) | Updated `sync_visual()` with optional default parameters for `FLUTTER`, `HOP`, `WALK`/`TROT` gait arcs, `IDLE` bobbing, and `turn_blend` horizontal scaling. |
| `scripts/test/test_wildlife_natural_movement.gd` | Untracked (`??`) | Added 64-assertion headless test suite covering species configs, desynchronization, visual interpolation/gait/turn/idle bobbing, multi-step bursts, anti-oscillation, fleeing, biome/walkability, Fog of War, hunting, and Save/Load. |
| `scripts/world/wildlife_config.gd.uid`, `scripts/world/wildlife_manager.gd.uid`, `scripts/world/wildlife_actor.gd.uid`, `scripts/test/test_wildlife_natural_movement.gd.uid`, `scripts/test/test_wildlife_ecosystem.gd`, `scripts/test/test_wildlife_ecosystem.gd.uid` | Untracked (`??`) | Godot `.uid` resource metadata files and existing Phase 6 wildlife ecosystem test file present in the working tree. |

*(No production files outside `scripts/world/wildlife_*.gd` were modified.)*

---

## 3. Technical Implementation

### `WildlifeConfig` Changes (`scripts/world/wildlife_config.gd`)
Added `enum GaitType { FLUTTER = 0, HOP = 1, WALK = 2, TROT = 3 }` and species-specific tuning fields in `SPECIES_DEFS`:

| Species | `gait_type` | `burst_min..max` | `turn_persistence` | `wander_radius` | `hop_height` | `idle_min..max` | `idle_bob_amp` / `freq` |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `bird` | `FLUTTER` (0) | `2..5` | `0.70` | `10` | `5.0` | `1.6..3.8` | `0.6` / `3.2` |
| `frog` | `HOP` (1) | `1..2` | `0.45` | `5` | `4.0` | `2.4..5.6` | `0.5` / `1.8` |
| `rabbit` | `HOP` (1) | `2..4` | `0.55` | `7` | `3.5` | `1.8..4.2` | `0.7` / `3.6` |
| `deer` | `WALK` (2) | `3..6` | `0.80` | `9` | `1.2` | `2.8..6.2` | `0.4` / `1.5` |
| `wild_boar` | `TROT` (3) | `2..4` | `0.60` | `7` | `1.5` | `2.4..5.0` | `0.8` / `2.8` |
| `mountain_goat` | `WALK` (2) | `2..4` | `0.65` | `6` | `2.2` | `2.4..5.0` | `0.5` / `2.0` |

### `WildlifeManager` Movement Logic (`scripts/world/wildlife_manager.gd`)
- **Record initialization (`_make_animal_record`):** Initializes `prev_cell`, `last_dir`, `burst_remaining`, `speed_jitter` (`_rng.randf_range(0.88, 1.12)`), `anim_phase` (`_rng.randf_range(0.0, TAU)`), `turn_blend` (`1.0`), and staggered initial `state_timer`.
- **Multi-step bursts & deceleration (`advance_simulation`):**
  - When entering a wander from `IDLE`, `burst_remaining` is rolled in `[burst_min, burst_max]`.
  - On completing a step (`move_progress >= 1.0`), `prev_cell` is updated and `burst_remaining` is decremented. If `burst_remaining > 0`, `_pick_wander_cell()` immediately selects the next cell without dropping to `IDLE`. When `burst_remaining == 0` (or no valid cell exists), the animal transitions to `IDLE` with a species-specific `state_timer`.
  - On the final step of a wandering burst (`burst_remaining <= 1`), visual progress uses `smoothstep(0.0, 1.0, prog)` for natural deceleration.
- **Anti-oscillation, tether & turn persistence (`_pick_wander_cell`):**
  - Filters cardinal neighbors by `nav.is_cell_walkable()`, `IsoMath.grid_distance(nb, world_data.center_spawn) > 4`, and `WildlifeConfig.is_biome_allowed()`.
  - Excludes `prev_cell` whenever other valid biome-matched neighbors exist.
  - Applies a soft `wander_radius` tether around `home_cell` (preferring cells within `wander_radius`, or stepping closer if outside).
  - Applies `turn_persistence` probability to continue along `last_dir` when available.
- **Isometric facing & turn smoothing (`_apply_step_facing`):**
  - Computes `dx_screen = IsoMath.map_to_local(to_cell).x - IsoMath.map_to_local(from_cell).x`.
  - Ignores near-zero screen X deltas (`absf(dx_screen) <= 0.01`); when `flip_h` changes, resets `turn_blend = 0.0`, which recovers toward `1.0` at `sim_dt * 7.0`.

### `WildlifeActor` Visual Interpolation and Animation (`scripts/world/wildlife_actor.gd`)
- `sync_visual(world_pos, state, flip_h, move_t = 0.0, is_moving = false, anim_time = 0.0, turn_blend = 1.0)` preserves optional defaults for backwards compatibility with existing callers.
- While moving (`is_moving == true`):
  - `FLUTTER`: `y_off -= sin(t * PI) * hop_h + absf(sin(t * PI * 3.0)) * 1.2`
  - `HOP`: `y_off -= sin(t * PI) * hop_h` and subtle vertical stretch `sy = 1.0 + sin(t * PI) * 0.12`
  - `WALK` / `TROT`: `y_off -= absf(sin(t * PI * 2.0)) * hop_h`
- While `IDLE` (`is_moving == false`): applies `y_off += sin(anim_time * bob_freq) * bob_amp`. Stops immediately in `BEING_HUNTED` (base offset `-5.0`).
- Applies `turn_blend` smoothing via `_sprite.scale = Vector2(lerpf(0.35, 1.0, clampf(turn_blend, 0.0, 1.0)), sy)`.

### RNG and Determinism Considerations
- Initial population placement and initial state generation remain deterministic from `world_data.seed_value` + `WildlifeConfig.WILDLIFE_RNG_SALT`.
- Simulation movement uses the manager's dedicated `_rng` instance (no global `randf()`/`randi()` calls), keeping simulation self-contained and non-perturbing to `WorldGenerator`.

---

## 4. Test Results

All tests below were executed headless during the implementation run using isolated `APPDATA` (`$env:APPDATA = Join-Path $env:TEMP "ku_test_appdata_wl"`):

```powershell
$env:APPDATA = Join-Path $env:TEMP "ku_test_appdata_wl"
$godot = "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe"
$proj = "e:\KINGDOMS UNBOUND\kingdoms-unbound"

& $godot --headless --path $proj --script "res://scripts/test/test_wildlife_natural_movement.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_wildlife_ecosystem.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_hunter_closure.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_cookhouse_closure.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_save_load.gd"
& $godot --headless --path $proj --script "res://scripts/test/test_fog_of_war_reconnaissance.gd"
```

Recorded results from the implementation run:
- `test_wildlife_natural_movement.gd`: **64 passed, 0 failed**
- `test_wildlife_ecosystem.gd`: **36 passed, 0 failed**
- `test_hunter_closure.gd`: **1076 passed, 0 failed**
- `test_cookhouse_closure.gd`: **33 passed, 0 failed**
- `test_save_load.gd`: **182 passed, 0 failed**
- `test_fog_of_war_reconnaissance.gd`: **127 passed, 0 failed**

No additional tests beyond those listed above were executed.

---

## 5. Performance

Measured via headless scratch benchmark (`bench_wildlife.gd`) over 300 simulation frames on a 128×128 generated world (`seed=12345`):
- **Active animals:** 26
- **Frames simulated:** 300 (`delta = 0.016`, `speed_mult = 1.0`)
- **Average `advance_simulation()` update:** `0.2022 ms`
- **Maximum `advance_simulation()` update:** `0.4210 ms`
- **A* pathfinding calls:** `0`

**Benchmark limitations:**
- Executed headless (`--headless`) without GPU/D3D12 rasterization overhead.
- Active animal count was the deterministic seed-12345 spawn count (`26`), below the theoretical `MAX_TOTAL_POPULATION = 70` cap.

---

## 6. Visual Verification

- **Agent-executed checks:** Headless automated assertions verified `WildlifeActor.position` mid-cell interpolation, `_sprite.offset.y` gait/idle-bobbing deltas, `_sprite.scale.x` `turn_blend` scaling, and `BEING_HUNTED` bobbing halt.
- **Live D3D12 / in-game viewport inspection:** **NOT VERIFIED by the Agent.** All Agent runs used `--headless`. Visual look-and-feel in the live D3D12 game viewport remains to be confirmed by the user in-game.

---

## 7. Compatibility and Regression

- **Wildlife ecosystem:** Preserved (`test_wildlife_ecosystem.gd`: 36 passed, 0 failed).
- **Hunting and Cookhouse:** Preserved (`test_hunter_closure.gd`: 1076 passed, 0 failed; `test_cookhouse_closure.gd`: 33 passed, 0 failed).
- **Fog of War:** Preserved; visibility checks continue to read logical `rec["cell"]` (`test_fog_of_war_reconnaissance.gd`: 127 passed, 0 failed).
- **Save/Load:** Preserved; `serialize()` / `deserialize_or_init()` roundtrip passes and restores/initializes presentation fields cleanly (`test_save_load.gd`: 182 passed, 0 failed; `test_wildlife_natural_movement.gd` Case 9).
- **Navigation and biome constraints:** Preserved; all wandering and fleeing steps enforce `nav.is_cell_walkable()`, settlement exclusion, and `WildlifeConfig.is_biome_allowed()`.
- **Monster Movement and Phase 9:** Untouched; no `monster_*` files were modified.

---

## 8. Git Status

- **Current branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Wildlife-related untracked (`??`) files from `git status --short scripts/world/wildlife* scripts/test/test_wildlife*`:**
  - `?? scripts/test/test_wildlife_ecosystem.gd`
  - `?? scripts/test/test_wildlife_ecosystem.gd.uid`
  - `?? scripts/test/test_wildlife_natural_movement.gd`
  - `?? scripts/test/test_wildlife_natural_movement.gd.uid`
  - `?? scripts/world/wildlife_actor.gd`
  - `?? scripts/world/wildlife_actor.gd.uid`
  - `?? scripts/world/wildlife_config.gd`
  - `?? scripts/world/wildlife_config.gd.uid`
  - `?? scripts/world/wildlife_manager.gd`
  - `?? scripts/world/wildlife_manager.gd.uid`
- Nothing was staged, committed, pushed, or discarded.

---

## 9. Remaining Issues

1. **Live D3D12 visual verification:** Not yet performed in a graphical game session (all automated verification was `--headless`).
2. **Uncommitted working tree files:** The wildlife scripts, `.uid` files, test files, and this report remain untracked/unstaged in the working tree awaiting user review/commit.
