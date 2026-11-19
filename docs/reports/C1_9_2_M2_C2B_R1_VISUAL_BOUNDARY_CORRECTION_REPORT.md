# C1.9.2 M2-C2B-R1 — Fog-State Boundary Visual Correction Audit & Prototype Report

**Date:** 2026-11-16  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Milestone:** C1.9.2 — M2-C2B-R1 (STOP before M2-C3 for owner review)  
**Engine:** Godot `v4.7.stable.official.5b4e0cb0f` (`D3D12 12_0 - Forward+` & headless)

---

## 1. Screenshot Diagnosis

Visual inspection of the M2-C2B composite capture (`02_composite_day_1x.png` / `baseline_100x.png`) identified four distinct visual defects:
1. **Settlement `VISIBLE <-> EXPLORED_NOT_VISIBLE` boundary:** Razor-sharp zig-zag staircase of isometric tile diamonds (`32×16 px` cells) cutting around the Town Hall and houses.
2. **`EXPLORED_NOT_VISIBLE <-> UNEXPLORED` boundary:** Abrupt step jump from dark cool mist (`alpha = 0.46`) to `100%` opaque bright cloud sea along the exact isometric tile diamond perimeter.
3. **Preview envelope inside `UNEXPLORED` (`HUNTER_SCOUT` + `SOLDIER` over coastline):** Soft radial cutout, plus in the initial smooth-transition prototype (`option_a` v1) an unintended `0.46` dark mist tint leaked into the `UNEXPLORED` preview core because `mist_alpha` did not gate on `(1.0 - unexp_factor)` (fixed in production).
4. **Pale `UNEXPLORED` cloud sea:** Low-contrast `0.80–0.99` gradient across large `1180 px` / `680 px` texture scales lacking mid-frequency billowing cloud-bank structure.

---

## 2. Root Cause per Boundary Type

| Boundary Type | Exact Root Cause in M2-C2B Shader / Texture Pipeline |
|---|---|
| `VISIBLE` <-> `EXPLORED_NOT_VISIBLE` | `fog_state_tex` (`128×128`, `FORMAT_R8`) used `filter_nearest` + hard shader `step(0.75, fog_state)` and `if (is_visible > 0.5) discard;`, locking the visual edge to individual `32×16 px` isometric tile diamonds. |
| `EXPLORED_NOT_VISIBLE` <-> `UNEXPLORED` | `step(fog_state, 0.25)` + `else if (is_explored_not_vis > 0.5)` switched instantaneously from `vec4(0.06, 0.09, 0.14, 0.46)` to `opaque_sea` (`a = 1.0`) along the same nearest-neighbor texel grid. |
| Preview Envelope inside `UNEXPLORED` | `envelope_tex` (`terrain_preview_envelope.gdshader`) already produced smooth C1.9.1 SDF transitions (`filter_linear`), so it had no diamond staircase; only the cloud-bank contrast and mist-gating needed correction. |
| Outer Map Bounds | `mask_uv` outside `[0, 1]` falls back to `preview_sd = 300.0`, `exp_cov = 0.0`, `vis_cov = 0.0` (`100%` seamless world-space `sea_tex`/`bank_tex` cloud sea, no viewport/map frame). |

---

## 3. Option A / B / C Comparison (Isolated D3D12 Prototype, Seed `12345`)

| Criterion | Option A: GPU `SubViewport` (`256×256` Isotropic Gaussian Coverage) | Option B: CPU Soft Coverage (`128×128` `FORMAT_RG8`) | Option C: Shader 9-Tap over `filter_nearest` `fog_state_tex` |
|---|---|---|---|
| **Visual Quality (`0.75x`/`1.0x`/`1.5x`)** | **Smooth, zero diamond staircase**; isotropic world-space feathering + organic cloud-bank edge displacement | **Smooth, zero diamond staircase**; clean boundary feathering | Faint residual diamond steps because each tap snaps on `filter_nearest` texels |
| **Memory** | `256 KB` VRAM (`256×256` `SubViewport`) + `32 KB` `fog_state_tex` | `32 KB` CPU + `32 KB` GPU (`FORMAT_RG8`) + `32 KB` `fog_state_tex` | `32 KB` `fog_state_tex` only |
| **Full Rebuild Cost** | `0.01 ms` CPU (`UPDATE_ONCE`); first-frame shader compile `244.8 ms` | `51.37–54.68 ms` CPU + `0.18 ms` upload | `0.00 ms` extra |
| **Incremental Dirty Cost** | **`0.086 ms` CPU** (25 cells) + `UPDATE_ONCE` GPU pass | `~0.4 ms` CPU dirty-rect + `0.02 ms` upload | `0.04 ms` CPU (`fog_state_tex` only) |
| **Idle Cost** | **`0.000 ms` CPU / `0.000 ms` GPU** (`UPDATE_DISABLED`) | `0.000 ms` | `0.000 ms` (extra 9 texture fetches/frag) |
| **Complexity / Rollback** | Isolated `FogTransitionViewport` + 1 shader file | CPU separable blur + dirty-rect maintenance | Shader-only, but inferior visual result |

---

## 4. Selected Solution & Rationale

**Selected:** **Option A (GPU `SubViewport` Visual Coverage Pass — `FogTransitionViewport` `256×256` + Volumetric 3-Octave Cloud Shading)**, keeping the exact discrete `128×128` `FORMAT_R8` `fog_state_tex` completely intact.

**Rationale:**
1. Eliminates all isometric tile-diamond staircases (`VISIBLE <-> EXPLORED_NOT_VISIBLE` and `EXPLORED_NOT_VISIBLE <-> UNEXPLORED`) while keeping `FogOfWar` and `fog_state_tex` 100% discrete and authoritative.
2. Avoids the `51–55 ms` CPU spike of full-map CPU blurring on world load / save load (`0.086 ms` CPU on 25-cell incremental updates, `0.000 ms` idle via `UPDATE_DISABLED`).
3. Adds a 3rd cloud octave (`b2` at `/ 310.0`) and 4-stop cloud shading (`col_shadow -> col_mist -> col_body -> col_top`) for richer volumetric cloud-bank structure without generic post-process blur.
4. Simple rollback: `use_cloud_sea_composite` remains `false` by default and `FogTransitionViewport` is cleanly freed in `cleanup_cloud_sea_composite()`.

---

## 5. Before / After Screenshots

Captured on D3D12 Forward+ (`seed = 12345`, `Day` `12:00`, `0.75x` / `1.0x` / `1.5x` zoom) in conversation scratch:
- **Before (M2-C2B Baseline):** `m2_c2b_r1_proto/baseline_075x.png`, `baseline_100x.png`, `baseline_150x.png` — sharp isometric diamond staircase around settlement, flat pale cloud sea.
- **Prototype Comparison:** `m2_c2b_r1_proto/option_a_{075x,100x,150x}.png`, `option_b_{075x,100x,150x}.png`, `option_c_{075x,100x,150x}.png`.
- **After (Production M2-C2B-R1):** `m2_c2b_captures/02_composite_day_1x.png` — smooth organic cloud-bank transitions around settlement, clear `UNEXPLORED` preview over coastline (zero mist tint leakage), rich volumetric cloud banks, and zero map-edge frame.

---

## 6. Entity Visibility Safety Results (`test_cloud_sea_visibility_safety.gd`)

Executed on D3D12 Forward+: **11 passed, 0 failed** (`exit=0`):
- **Hidden Resource Prop (`prop_nodes_by_cell`):** Real prop at `UNEXPLORED (1, 42)` remained `visible == false` under active `TOWN_HALL` preview.
- **Undiscovered POI (`poi_nodes_by_id`):** Real POI `poi_1` at `UNEXPLORED (99, 44)` remained `visible == false` under active preview.
- **Wildlife (`wildlife_mgr`):** Real wildlife `wl_bird_01` at non-visible `(89, 17)` remained `visible == false` under active preview.
- **Monsters (`monster_mgr`):** No real monsters spawned at Day 1 start; verified via isolated monster fixture gated by `FogOfWar.is_visible()` (`visible == false`).
- **Enemy Military (`enemy_military_mgr`):** No real enemies spawned at Day 1 start; verified via isolated enemy fixture gated by `FogOfWar.is_visible()` (`visible == false`).
- **FogOfWar Integrity:** `_fog_state_bytes` remained byte-for-byte identical and previewed cells remained `UNEXPLORED`.

---

## 7. Performance Measurements & Regression Suite Results

### Observed Performance (`test_cloud_sea_visibility_safety.gd` & `test_cloud_sea_fog_state_composition.gd`, D3D12)
- `fog_state_tex` memory: `32 KB` (`128×128` `FORMAT_R8`)
- `FogTransitionViewport` memory: `256 KB` VRAM (`256×256`)
- Steady-state 25-cell incremental update: `0.086 ms` CPU (`update_fog_state_texture_dirty_cells` + `UPDATE_ONCE` schedule); `fog_state_tex` upload `0.019 ms`; `transition_vp_gpu = 0.000 ms`
- Idle cost (10 idle frames): **`0` `fog_state_tex` uploads, `0` `FogTransitionViewport` updates** (`avg_frame_ms = 6.516 ms`)

### Regression Suites (Observed After Final Edit)
| Suite | Renderer | Passed | Failed | Exit |
|---|---|---:|---:|---:|
| `scripts/test/test_cloud_sea_visibility_safety.gd` | D3D12 Forward+ | 11 | 0 | 0 |
| `scripts/test/test_cloud_sea_fog_state_composition.gd` | D3D12 Forward+ | 19 | 0 | 0 |
| `scripts/test/test_cloud_sea_composite.gd` | D3D12 Forward+ | 24 | 0 | 0 |
| `scripts/test/test_terrain_preview_gpu_equiv.gd` | D3D12 Forward+ | 60 | 0 | 0 |
| `scripts/test/test_world_view_preview_lifecycle.gd` | D3D12 Forward+ | 16 | 0 | 0 |
| `scripts/test/test_fog_of_war_reconnaissance.gd` | Headless | 127 | 0 | 0 |
| `scripts/test/test_fog_rendering.gd` | Headless | 24 | 0 | 0 |
| `scripts/test/test_fog_debug_toggle.gd` | Headless | 15 | 0 | 0 |
| `scripts/test/test_fog_cloud_overlay.gd` | Headless | 61 | 0 | 0 |

---

## 8. Exact Modified & Created Files

| File | Change |
|---|---|
| `shaders/fog/fog_transition_coverage.gdshader` | Created — `256×256` isotropic world-space Gaussian coverage pass reading `fog_state_tex` (`filter_nearest`) |
| `shaders/fog/cloud_sea_composite.gdshader` | Modified — added `transition_tex`, smooth organic cloud/mist boundary blending, `(1.0 - unexp_factor)` mist gating, and 3-octave volumetric cloud shading |
| `scripts/world/world_view.gd` | Modified — added `_fog_transition_viewport` (`UPDATE_DISABLED` when idle, `UPDATE_ONCE` on dirty upload) and cleanup |
| `scripts/test/test_cloud_sea_visibility_safety.gd` | Created — 11-assertion entity visibility safety & idle/incremental performance suite |
| `scripts/test/test_cloud_sea_fog_state_composition.gd` | Modified — updated single-cell probe to `5×5` patch + 1-frame wait for `FogTransitionViewport` `UPDATE_ONCE` |
| `scripts/test/test_world_view_preview_lifecycle.gd` | Modified — updated `vp_count_before >= 1 and vp_count_after == vp_count_before` to account for `FogTransitionViewport` |
| `docs/reports/C1_9_2_M2_C2B_R1_VISUAL_BOUNDARY_CORRECTION_REPORT.md` | Created — this report |

---

## 9. Remaining Risks

1. **Monster & Enemy Military Day-1 Spawn Gap:** On seed `12345` at Day 1 start, `monster_mgr` and `enemy_military_mgr` had no live spawned actors, so those two checks used isolated `FogOfWar.is_visible()` fixtures rather than live actors (real resource props, POIs, and wildlife were verified with live scene nodes).
2. **`FogOfWar` Manhattan Circle Silhouette:** Because `FogOfWar` reveals cells in Manhattan diamonds (`abs(dx) + abs(dy) <= r`), which map to horizontal/vertical rectangles in isometric screen space, very large revealed areas still have a softly rounded-rectangular macro silhouette softened by cloud wisps.

---

## 10. Recommendation

**READY** — Ready for owner review and **M2-C3** authorization. `use_cloud_sea_composite` remains `false`, legacy fog remains intact, `FogOfWar` and `SaveManager` are unmodified, and no commits or pushes were made.
