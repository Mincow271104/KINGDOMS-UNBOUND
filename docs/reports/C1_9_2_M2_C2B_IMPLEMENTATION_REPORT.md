# C1.9.2 M2-C2B — Fog-State Composition & CloudSeaComposite Validation Report

**Date:** 2026-11-16  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Milestone:** C1.9.2 — M2-C2B (STOP before M2-C3 for owner review)  
**Engine:** Godot `v4.7.stable.official.5b4e0cb0f` (`D3D12 12_0 - Forward+` & headless)

---

## 1. Executive Summary

M2-C2B extends the production `CloudSeaComposite` system so it visually composes `FogOfWar` gameplay states (`UNEXPLORED`, `EXPLORED_NOT_VISIBLE`, `VISIBLE`), the `TerrainPreviewField` / `TerrainPreviewRenderer` GPU envelope, and the approved C1.9.1 cloud sea textures, while keeping `FogOfWar` as the sole gameplay discovery and entity visibility authority and leaving `use_cloud_sea_composite = false` (legacy fog presentation active) by default.

All **10 test suites** (including the new 19-assertion GPU/CPU composition suite `test_cloud_sea_fog_state_composition.gd` and the updated 24-assertion `test_cloud_sea_composite.gd`) passed with **0 failures** (`549/549` total assertions across all 10 suites). Visual captures across Legacy vs Composite, `0.75x`/`1.0x`/`1.5x` camera zoom, and `Dawn`/`Day`/`Dusk`/`Night` `DayNightModulate` tinting confirmed correct visual separation of all four states.

---

## 2. Files Modified & Created

| File | Role | Status |
|---|---|---|
| `shaders/fog/cloud_sea_composite.gdshader` | Added `fog_state_tex` (`filter_nearest`) and independent visual composition for `VISIBLE`, `EXPLORED_NOT_VISIBLE`, `UNEXPLORED` preview, and `UNEXPLORED` cloud sea | Modified |
| `scripts/world/world_view.gd` | Added compact `FORMAT_R8` `_fog_state_tex` pipeline, dirty-cell incremental patching (`update_fog_state_texture_dirty_cells`), full sync (`sync_fog_state_texture_full`), rebind, and cleanup hooks | Modified |
| `scripts/test/test_cloud_sea_fog_state_composition.gd` | New 19-assertion M2-C2B composition, incremental upload, save/load reconstruction, and `FogOfWar` non-mutation test suite | Created |
| `scripts/test/test_cloud_sea_composite.gd` | Updated isolated `0`-source / `1`-source fixture check to bind a fresh `UNEXPLORED` `FogOfWar` instance via `rebind_terrain_preview_fog` (restoring the live `fog` afterward) | Modified |
| `docs/reports/C1_9_2_M2_C2B_IMPLEMENTATION_REPORT.md` | This M2-C2B validation report | Created |

Unmodified by design: `scripts/world/fog_of_war.gd`, `scripts/persistence/save_manager.gd`, `scripts/world/fog_cloud_layer.gd`, `use_cloud_sea_composite` default (`false`), and gameplay preview source wiring (Town Hall / Hunter / Soldier).

---

## 3. Fog-State Representation & Texture Pipeline

- **Format & Encoding:** `Image.FORMAT_R8` (`1 byte/pixel`, `128×128` -> `32 KB` backing byte buffer + `ImageTexture`), sampled with `filter_nearest, repeat_disable`:
  - `UNEXPLORED` (`FogOfWar.State.UNEXPLORED = 0`) -> byte `0` (`< 0.25` in shader)
  - `EXPLORED_NOT_VISIBLE` (`FogOfWar.State.EXPLORED = 1`) -> byte `128` (`0.25 <= val < 0.75` in shader)
  - `VISIBLE` (`FogOfWar.State.VISIBLE = 2`) -> byte `255` (`>= 0.75` in shader)
- **Full Sync (`sync_fog_state_texture_full(force := false)`):**
  - Skips GPU upload (`0 uploads`) if `fog_state_tex` is already valid and the byte buffer is unchanged (`force == false`).
  - Called during `_setup_cloud_sea_composite()`, `_sync_full_fog_layer()`, `rebind_terrain_preview_fog()`, and `_sync_full_fog_and_minimap()` (covering Save/Load & world reset reconstruction).
- **Incremental Dirty-Cell Update (`update_fog_state_texture_dirty_cells(dirty_cells)`):**
  - Hooked into `_update_fog_visuals(dirty_cells)`.
  - Writes only changed cells in `_fog_state_bytes` and performs at most **1 batched `ImageTexture.update()`** per frame when at least one cell changed (`0 uploads` when no cell byte actually changed).

---

## 4. Shader Composition Rules (`shaders/fog/cloud_sea_composite.gdshader`)

Using `fog_state = texture(fog_state_tex, clamp(v_map_uv, 0.0, 1.0)).r`:

1. **`VISIBLE` (`fog_state >= 0.75`):** `discard;` — zero cloud or fog overlay; terrain, buildings, and units render completely clear.
2. **`EXPLORED_NOT_VISIBLE` (`0.25 <= fog_state < 0.75`):** `COLOR = vec4(0.06, 0.09, 0.14, 0.46);` — subdued cool mist darkening over previously discovered terrain; no opaque cloud sea obscures remembered layout.
3. **`UNEXPLORED` (`fog_state < 0.25`):** Driven by `envelope_tex` (`r = clear_factor`, `g = rim_factor`) and C1.9.1 multi-layer cloud textures (`sea_tex`, `bank_tex`):
   - Inside preview core/envelope: smooth C1.9.1 cloud-parting reveal showing terrain morphology underneath.
   - Outside preview envelope: `100%` opaque luminous cloud sea.
4. **Lighting Invariance:** `CloudSeaComposite` remains parented under `World` (`modulate = Color.WHITE`) with only `World/DayNightModulate` active, avoiding compounded tinting or shadow clamping.

---

## 5. Verification & Regression Results

All runs below were executed after the final production and test edits:

| Suite | Renderer | Passed | Failed | Exit |
|---|---|---:|---:|---:|
| `scripts/test/test_cloud_sea_fog_state_composition.gd` | D3D12 Forward+ | 19 | 0 | 0 |
| `scripts/test/test_cloud_sea_composite.gd` | D3D12 Forward+ | 24 | 0 | 0 |
| `scripts/test/test_terrain_preview_gpu_equiv.gd` | D3D12 Forward+ | 60 | 0 | 0 |
| `scripts/test/test_terrain_preview_field.gd` | Headless | 21 | 0 | 0 |
| `scripts/test/test_world_view_preview_lifecycle.gd` | Headless | 16 | 0 | 0 |
| `scripts/test/test_fog_of_war_reconnaissance.gd` | Headless | 127 | 0 | 0 |
| `scripts/test/test_fog_rendering.gd` | Headless | 24 | 0 | 0 |
| `scripts/test/test_fog_debug_toggle.gd` | Headless | 15 | 0 | 0 |
| `scripts/test/test_fog_cloud_overlay.gd` | Headless | 61 | 0 | 0 |
| `scripts/test/test_save_load.gd` | Headless | 182 | 0 | 0 |

### Observed Performance Metrics (`test_cloud_sea_fog_state_composition.gd` on D3D12)
- `initial_full_gen=0.000ms upload=0.026ms mem=32KB`
- Repeated identical `sync_fog_state_texture_full(false)`: `0` uploads
- `inc_25cells=0.028ms upload=0.018ms` (25 dirty cells batched into `1` upload)
- Repeating same `dirty_cells` without state change: `0` uploads
- `composite_probe_gpu=0.000ms`

---

## 6. Visual Inspection Summary

D3D12 screenshots captured via `capture_m2_c2b.gd` (in conversation scratch `m2_c2b_captures/`) verified:
- **Legacy (`01_legacy_day_1x.png`) vs Composite (`02_composite_day_1x.png`):** Legacy presentation remains 100% intact when `use_cloud_sea_composite = false`. In isolated composite mode, `VISIBLE` center is crystal clear, `EXPLORED_NOT_VISIBLE` shows subdued cool mist (`alpha = 0.46`), synthetic `HUNTER_SCOUT` / `SOLDIER` sources in `UNEXPLORED` terrain open soft organic C1.9.1 cloud-sea previews over coastline/water/grass, and surrounding `UNEXPLORED` territory stays 100% opaque cloud sea.
- **Zoom Invariance (`03_composite_day_075x.png`, `04_composite_day_15x.png`):** World-space cloud patterns, preview boundaries, and fog-state boundaries remain locked to world coordinates across `0.75x`, `1.0x`, and `1.5x`.
- **Day/Night Cycle (`05_composite_dawn_1x.png`, `06_composite_dusk_1x.png`, `07_composite_night_1x.png`):** Single `World/DayNightModulate` node cleanly tints the cloud sea across Dawn, Day, Dusk, and Night without double-tinting.
- **Honest Visual Note for M2-C3 Tuning:** Because `fog_state_tex` uses `filter_nearest`, the boundary between `VISIBLE` / `EXPLORED_NOT_VISIBLE` / `UNEXPLORED` renders with crisp isometric tile-diamond edges matching `FogOfWar` cells, whereas the preview envelope has smooth SDF transitions.

---

## 7. M2-C3 Readiness & Scope Boundary

- `use_cloud_sea_composite` remains `false` by default; legacy `fog_tile_layer`, `fog_cloud_layer`, and `cloud_sea_base` remain active.
- No gameplay preview sources (Town Hall, Hunter, Soldier) are wired yet.
- Ready for owner review and **M2-C3** authorization (connecting approved gameplay preview sources and switching active presentation if approved).
