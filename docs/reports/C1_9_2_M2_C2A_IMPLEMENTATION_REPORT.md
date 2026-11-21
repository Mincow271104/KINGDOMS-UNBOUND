# C1.9.2 — M2-C2A Implementation Report: CloudSeaComposite Production Foundation

**Project:** KINGDOMS UNBOUND  
**Engine:** Godot 4.7-stable  
**Milestone:** C1.9.2 — M2-C2A (CloudSeaComposite Production Foundation)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Status:** PASS — Ready for Owner Review (M2-C2B not started)

---

## 1. Baseline & Git Preservation Evidence

- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Pre-M2-C2A `git status --short` count:** `435` entries (all pre-existing modified/untracked files preserved untouched).
- **M2-C2A Changes Only:**
  - **Modified:** `scripts/world/world_view.gd`
  - **Created:** `shaders/fog/cloud_sea_composite.gdshader`
  - **Promoted Assets:** `assets/fog/cloud_wisps_sea_1024.png`, `assets/fog/cloud_banks_macro_1024.png`
  - **Created:** `scripts/test/test_cloud_sea_composite.gd`
  - **Created:** `docs/reports/C1_9_2_M2_C2A_IMPLEMENTATION_REPORT.md`
- **Explicitly Untouched:** Original scratch assets, `SaveManager`, `FogOfWar`, `fog_tile_layer` / `fog_cloud_layer` / `cloud_sea_base` default runtime behavior, `set_debug_fog_disabled()` semantics, `World/DayNightModulate`, and gameplay entity managers. No staging, committing, or pushing performed.

---

## 2. Exact Asset & Shader Provenance

- **Promoted Textures (copied byte-for-byte from approved C1.9.1 / C1.8 prototype assets; originals unmodified):**
  - `scratch/c1_8_cloud_reference_redesign/assets/cloud_wisps_sea_1024.png` -> `assets/fog/cloud_wisps_sea_1024.png` (`647,511` bytes)
  - `scratch/c1_8_cloud_reference_redesign/assets/cloud_banks_macro_1024.png` -> `assets/fog/cloud_banks_macro_1024.png` (`699,463` bytes)
- **Production Composite Shader:**
  - `shaders/fog/cloud_sea_composite.gdshader` — ported directly from `scratch/c1_9_1_shape_correction/shaders/c1_9_1_envelope_cloud.gdshader` preserving all uniforms (`sea_tex`, `bank_tex`, `envelope_tex`, `map_size`, `world_seed_f`, `debug_mode`), world-space `v_world_pos` transform, `mask_uv` formula, `preview_sd` / `core_sd` unpack scales, and luminous cloud colors (`col_mist`, `col_body`, `col_top`).

---

## 3. Composite Architecture (`scripts/world/world_view.gd`)

- Added `cloud_sea_composite: Polygon2D = null` owned by `WorldView` under `world_root` (`World`, `z_index = 7`, `TEXTURE_FILTER_LINEAR`).
- Added disabled-by-default switch `use_cloud_sea_composite: bool = false` so normal gameplay continues using legacy fog layers with zero duplicate opaque overlays.
- `_setup_cloud_sea_composite()` (called in `_setup_fog_layer()`):
  - Reuses existing `cloud_sea_composite` without creating duplicates on repeated setup.
  - Builds 4-vertex isometric diamond polygon spanning `(-0.5, -0.5)` to `(mw - 0.5, mh - 0.5)` in grid space.
  - Binds `sea_tex`, `bank_tex` (via `_load_composite_cloud_texture()`, supporting both imported resources and `Image.load_from_file()` fallback), `envelope_tex = terrain_preview_renderer.get_envelope_texture()`, `map_size`, `world_seed_f`, and `debug_mode = 0`.
  - Keeps `cloud_sea_composite.modulate = Color.WHITE` so `World/DayNightModulate` is the **sole RGB tint authority**.
- Added `set_cloud_sea_composite_isolated_mode(enabled: bool)` for isolated A/B visual testing and `cleanup_cloud_sea_composite()` called in `_exit_tree()`.

---

## 4. Shader Compile Results

- `shaders/fog/cloud_sea_composite.gdshader` compiled cleanly under **D3D12 `12_0` Forward+** (`NVIDIA GeForce RTX 3050 Ti Laptop GPU`) with zero shader warnings or errors.

---

## 5. Texture & Coordinate Verification

- Verified `test_cloud_sea_composite.gd` (**24/24 assertions passed, 0 failed**, `exit=0`):
  - `CloudSeaComposite` created as child of `World` with `Color.WHITE` modulate and single `CanvasModulate` (`World/DayNightModulate`).
  - `sea_tex`, `bank_tex`, `envelope_tex`, and `map_size` bound accurately.
  - Disabled by default (`use_cloud_sea_composite == false`, `cloud_sea_composite.visible == false`), leaving legacy `fog_tile_layer`, `fog_cloud_layer`, and `cloud_sea_base` enabled and unchanged.
  - Repeated `_setup_fog_layer()` keeps `CloudSeaComposite` count at `1`.
  - Isolated-mode shader checks passed for `0` sources (opaque cloud sea), centered `Town Hall` fixture (terrain revealed at center, cloud sea outside), multiple overlapping + map-edge `(0, 127)` sources, `1.5x` zoom, and byte-for-byte `FogOfWar` preservation.
  - `cleanup_cloud_sea_composite()` frees the node and clears references.

---

## 6. Visual Screenshots & Findings

Captured on D3D12 `12_0` Forward+ (`world_seed = 12345`, `1280x720`):
- `m2_c2a_legacy_day.png`: Legacy fog presentation alone (unchanged).
- `m2_c2a_composite_day.png`: Isolated `CloudSeaComposite` with centered `Town Hall` + `Soldier` fixture at Day `12:00`.
- `m2_c2a_composite_dawn.png` (`06:00`), `m2_c2a_composite_dusk.png` (`18:00`), `m2_c2a_composite_night.png` (`00:00`): `World/DayNightModulate` tints the cloud sea smoothly without compounding or darkening alpha.
- `m2_c2a_composite_zoom_0.75.png` (`0.75x`), `m2_c2a_composite_zoom_1.50.png`: Softly rounded, slightly asymmetric luminous cloud sea with zero rectangular inner border, zero texture seams, zero UV drift, and zero screen-space swimming.

---

## 7. Regression Results (0 Failures Across All 9 Suites)

| Test Suite | Mode | Passed | Failed | Exit |
|---|---|---:|---:|---|
| `test_cloud_sea_composite.gd` | D3D12 Forward+ | 24 | 0 | 0 |
| `test_terrain_preview_gpu_equiv.gd` | D3D12 Forward+ | 60 | 0 | 0 |
| `test_terrain_preview_field.gd` | Headless | 21 | 0 | 0 |
| `test_world_view_preview_lifecycle.gd` | D3D12 Forward+ | 16 | 0 | 0 |
| `test_fog_of_war_reconnaissance.gd` | Headless | 127 | 0 | 0 |
| `test_fog_rendering.gd` | Headless | 24 | 0 | 0 |
| `test_fog_debug_toggle.gd` | D3D12 Forward+ | 15 | 0 | 0 |
| `test_fog_cloud_overlay.gd` | D3D12 Forward+ | 61 | 0 | 0 |
| `test_save_load.gd` | Headless | 182 | 0 | 0 |

---

## 8. Performance

Observed on D3D12 Forward+ (`test_terrain_preview_gpu_equiv.gd`):
- `1x` (`128x128`) envelope: `0.028–0.267 ms` pack, `0.009–0.017 ms` upload, `0.038–0.183 ms` SubViewport GPU (`1`–`128` sources), `0` GPU passes when idle (`UPDATE_DISABLED`).
- `2x` (`256x256`) envelope: `0.031–0.246 ms` pack, `0.014–0.018 ms` upload, `0.032–0.549 ms` SubViewport GPU (`1`–`128` sources).
- `CloudSeaComposite` renders as a single `Polygon2D` quad sampling 3 pre-generated textures; no per-frame CPU SDF work is performed.

---

## 9. Known Limitations

- `CloudSeaComposite` is intentionally disabled by default (`use_cloud_sea_composite = false`) in M2-C2A; legacy fog remains active until M2-C2B/M2-C3 transition.
- Newly copied `assets/fog/cloud_wisps_sea_1024.png` and `assets/fog/cloud_banks_macro_1024.png` do not yet have `.import` metadata generated by the editor, so `_load_composite_cloud_texture()` uses `Image.load_from_file()` fallback in headless/CLI runs until the editor imports them.

---

## 10. Explicit Verdict

**PASS** — `CloudSeaComposite` foundation, promoted assets, shader compilation, coordinate alignment, single Day/Night tint authority, isolated visual quality, and all 9 regression suites (530 total assertions, 0 failures) are verified.

**STOPPING HERE. Awaiting owner review before starting M2-C2B.**
