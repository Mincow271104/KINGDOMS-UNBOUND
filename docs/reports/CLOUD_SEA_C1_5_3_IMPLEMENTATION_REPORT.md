# KINGDOMS UNBOUND — C1.5.3 Hybrid Cloud Sea A/B Test Report

**Milestone:** C1.5.3 — Isolated Visual Prototype, Technical Validation & Owner Review  
**Date:** 2026-11-15  
**Engine:** Godot 4.7 (`Forward+`, `TEXTURE_FILTER_NEAREST`)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement` (`HEAD e1d379b93a48db018c7b412b896caa9592f6980c`)  
**Status:** Complete — Awaiting Owner Decision (No Production Integration Performed)

---

## 1. Executive Summary

This report documents an isolated Godot 4.7 A/B/C comparison evaluating whether adding a subdued, seamless pixel-art cloud-sea background (`CloudSeaBase`) beneath Version A foreground cloud banks improves visual continuity without sacrificing pixel-art cohesion, exploration readability, Day/Night atmosphere, or performance.

- **Variant 1 — `A_Medium` Baseline:** `418` foreground sprites, `44.13%` foreground coverage, no background layer.
- **Variant 2 — `Hybrid Standard`:** `256x256` seamless pixel-art `CloudSeaBase` + `418` `A_Medium` foreground sprites (`44.13%` fg coverage).
- **Variant 3 — `Hybrid Reduced`:** Same `CloudSeaBase` + `350` foreground sprites (`40.09%` fg coverage).

### Conclusion
**A. Hybrid Wins** (`Variant 2 — Hybrid Standard` primary recommendation, with `Variant 3 — Hybrid Reduced` as a lighter-footprint alternative). The subdued `256x256` pixel-art cloud floor eliminates the harsh `#0A0D14` black void in deep unexplored areas, preserves the A2 Organic Pixel-Mist Fringe via a `~1.5–2.5` tile dithered frontier transition, maintains crisp `12:00` Day and `22:00` Night readability, and adds virtually zero runtime frame cost (`6.10 ms` average frame time vs `6.10 ms` baseline; `0.026 ms` dirty mask GPU upload).

---

## 2. Git Baseline and Preservation Confirmation

- **Baseline Recorded:** `feature/package-3a-outpost-garrison-reinforcement`, `HEAD e1d379b93a48db018c7b412b896caa9592f6980c`, `404` pre-existing modified/untracked entries saved in `scratch/c1_5_3_baseline_git_status.txt`.
- **Preservation:** Zero production files (`FogOfWar`, `FogCloudLayer`, `WorldView`, `SaveManager`, `TerritoryManager`, `FogTileMapLayer`, `assets/fog/*`, or prior C1.1–C1.5.1 files) were modified.

---

## 3. Files Created

All C1.5.3 prototype files are isolated under `scratch/c1_5_3_hybrid_test/`, plus this report:

- `scratch/c1_5_3_hybrid_test/generate_cloud_base.py` — Seamless `256x256` pixel-art cloud-floor generator.
- `scratch/c1_5_3_hybrid_test/assets/cloud_sea_base_256.png` — Generated `256x256` RGBA seamless pixel-art base texture.
- `scratch/c1_5_3_hybrid_test/run_c1_5_3_hybrid_test.gd` — Isolated Godot 4.7 test harness (Day `12:00`, Night `22:00`, irregular scout pocket, mask benchmarks, determinism checks).
- `scratch/c1_5_3_hybrid_test/analyze_c1_5_3.py` — Pixel-coverage calculator and 8 comparison-sheet generator.
- `scratch/c1_5_3_hybrid_test/raw_results.json` & `scratch/c1_5_3_hybrid_test/metrics_summary.csv` — Raw and aggregated measurements.
- `scratch/c1_5_3_hybrid_test/screenshots/` — 21 individual full-res screenshots + 8 labeled comparison sheets.
- `docs/reports/CLOUD_SEA_C1_5_3_IMPLEMENTATION_REPORT.md` — This report.

---

## 4. Prototype Architecture

Inside the instantiated `WorldView/World` (`128x128`, seed `12345`), the production `FogCloudLayer` was disabled (`set_cloud_overlay_enabled(false)`) and replaced by two isolated test nodes:

1. `C153CloudSeaBase` (`Polygon2D`, `z_index = 6`): Covers the exact `128x128` isometric map diamond; enabled in Variants 2 and 3, hidden in Variant 1.
2. `C153ForegroundClouds` (`Node2D`, `z_index = 7`, `y_sort_enabled = true`, `TEXTURE_FILTER_NEAREST`): Hosts the deterministic Version A `Sprite2D` banks.

---

## 5. Variant Definitions

| Variant | `CloudSeaBase` | `target_banks` | `sup_min..max` | `target_bridges` | Foreground Sprites | FG Coverage | FG >=2x Overlap |
|---|---|---:|---:|---:|---:|---:|---:|
| **V1 — A_Medium Baseline** | Disabled | 82 | 3–6 | 68 | 418 | 44.13% | 14.54% |
| **V2 — Hybrid Standard** | Enabled (`z=6`) | 82 | 3–6 | 68 | 418 | 44.13% | 14.54% |
| **V3 — Hybrid Reduced** | Enabled (`z=6`) | 68 | 3–5 | 54 | 350 | 40.09% | 8.79% |

---

## 6. Background Texture Design and Parameters

`cloud_sea_base_256.png` (`256x256` RGBA) was generated on a `128x128` logical grid and upscaled `2x` via `Image.NEAREST` so each pixel-art block (`2x2` world px) matches Version A sprite texel density:

- **Synthesis:** Periodic 2D multi-octave value noise (`1:2` horizontal elongation) with gentle horizontal domain warping and `2x2` ordered Bayer dithering.
- **Palette (4 subdued dark-fantasy tones):** `#0B101B` (deep navy trough), `#101829` (base indigo), `#162138` (mid-slate), `#1C2A46` (subtle high-mist). Low contrast keeps foreground Version A banks visually dominant.
- **Sampling:** World-aligned `v_world_pos / 256.0` with `repeat_enable, filter_nearest`, `base_alpha = 0.96`.

---

## 7. Isometric Mask Mapping Explanation

An initial test revealed that `Polygon2D` with `texture == null` does not pass normalized `[0, 1]` `UV` coordinates reliably to fragment shaders. The shader was updated to compute exact isometric grid coordinates directly from `v_world_pos` using `IsoMath`'s inverse projection:

```glsl
float u_grid = (v_world_pos.x / 32.0) + (v_world_pos.y / 16.0);
float v_grid = (v_world_pos.y / 16.0) - (v_world_pos.x / 32.0);
vec2 mask_uv = (vec2(u_grid, v_grid) + 0.5) / map_size;
```

- `mask_uv` outside `[0.0, 1.0]^2` is discarded, guaranteeing zero bleed outside the playable `128x128` isometric diamond.
- `fog_mask` (`128x128` `ImageTexture`) maps `EXPLORED` and `VISIBLE` cells to `0.0` (completely hidden).

---

## 8. Frontier Transition Implementation

To preserve the A2 Organic Pixel-Mist Fringe (`z_index = 5`) cleanly without a hard seam:

- `_compute_cell_mask_value()` computes Manhattan distance `min_d` from each `UNEXPLORED` cell to the nearest `EXPLORED`/`VISIBLE` cell: `min_d <= 1 -> 0.0`, `min_d == 2 -> 0.42`, `min_d == 3 -> 0.78`, `min_d >= 4 -> 1.0`.
- `fog_mask` is sampled with `filter_linear` for smooth distance interpolation across tiles `1.5–3.0`, then thresholded against a world-space `4x4` Bayer matrix (`floor(v_world_pos * 0.5)`), producing a crisp pixel-art dithered fade-in behind the A2 fringe.

---

## 9. Rendering Order

Verified clean integer `z_index` layering inside `WorldView/World`:

1. Terrain / Entities / Buildings / Citizens (`z = 0`, `y_sort_enabled`)
2. `FogTileMapLayer` (`z = 5`): A2 Organic Pixel-Mist Fringe + dark base
3. `C153CloudSeaBase` (`z = 6`): Subdued seamless cloud floor (faded out within `1` tile of A2 fringe)
4. `C153ForegroundClouds` (`z = 7`): Version A foreground cloud banks
5. `CursorHighlight` (`z = 10`) & `HUD` (separate `CanvasLayer`, unaffected)

---

## 10. Day/Night Handling

Both `C153CloudSeaBase` and `C153ForegroundClouds` reside under `World`, so `World/DayNightModulate` (`Color(1,1,1,1)` at `12:00` DAY; `Color(0.52,0.60,0.84,1)` at `22:00` NIGHT) modulates them automatically. No extra multiplicative `apply_day_night_tint()` darkening was layered on top, preventing night double-darkening.

---

## 11. Performance Measurements

Measured in Godot 4.7 (`1280x720`, `128x128` world, RTX 3050 Ti Laptop GPU):

| Metric | V1 (`A_Medium`) | V2 (`Hybrid Standard`) | V3 (`Hybrid Reduced`) |
|---|---:|---:|---:|
| Foreground sprite count | 418 | 418 | 350 |
| Foreground coverage (V2 viewport) | 44.13% | 44.13% | 40.09% |
| Background coverage (deep unexplored) | N/A (`0%`) | 100.0% (masked) | 100.0% (masked) |
| Foreground initialization time (`init_ms`) | 1058.61 ms | 1034.89 ms | 792.40 ms |
| Initial full mask CPU build (`mask_init`) | N/A | 650.198 ms | 650.198 ms |
| Initial mask GPU upload (`tex_update_ms`) | N/A | 0.030 ms | 0.030 ms |
| Dirty mask CPU update (`113` cells) | N/A | 1.147 ms | 1.147 ms |
| Dirty mask GPU upload (`update()`) | N/A | 0.026 ms | 0.026 ms |
| Avg frame time (20 frames, View 2) | 6.10 ms | 6.10 ms | 6.84 ms |
| Visible cloud instances (V1 / V2 / V3 / V4) | 43 / 64 / 32 / 44 | 43 / 64 / 32 / 44 | 35 / 56 / 27 / 42 |
| Mask memory (`128x128` RGBA8 + `256x256` base) | 0 KB | ~320 KB VRAM | ~320 KB VRAM |

*Note:* `ImageTexture.update()` on `128x128` took **`0.026–0.030 ms`** on dirty events, confirming full `128x128` texture upload is negligible when event-driven.

---

## 12. Determinism and Exploration Tests

All checks passed in `run_c1_5_3_hybrid_test.gd`:

- **Foreground determinism:** Rebuilding `V2` twice with seed `12345` produced byte-identical sprite lists (`deterministic_sprites=true`).
- **Incremental vs. full mask equivalence:** Dirty-cell mask update after `reveal_circle` produced **byte-identical** `Image` data to a full mask rebuild (`inc_matches_full=true`).
- **Zero leaks:** `fg_leaks_before=0`, `fg_leaks_after=0`, `base_leaks_before=0`, `base_leaks_after=0`.
- **Irregular scout pocket + map bounds:** L-shaped scout pocket and post-reveal expansion cleared cleanly with zero `CloudSeaBase` bleed outside `[0..128, 0..128]`.

---

## 13. Screenshot Index

All sheets are under `scratch/c1_5_3_hybrid_test/screenshots/`:

1. [settlement_frontier_day.png](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_3_hybrid_test/screenshots/settlement_frontier_day.png)
2. [deep_cloud_sea_day.png](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_3_hybrid_test/screenshots/deep_cloud_sea_day.png)
3. [closeup_day.png](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_3_hybrid_test/screenshots/closeup_day.png)
4. [irregular_scout_pocket_before.png](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_3_hybrid_test/screenshots/irregular_scout_pocket_before.png)
5. [irregular_scout_pocket_after.png](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_3_hybrid_test/screenshots/irregular_scout_pocket_after.png)
6. [settlement_frontier_night.png](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_3_hybrid_test/screenshots/settlement_frontier_night.png)
7. [deep_cloud_sea_night.png](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_3_hybrid_test/screenshots/deep_cloud_sea_night.png)
8. [density_progression.png](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_3_hybrid_test/screenshots/density_progression.png)

---

## 14. Weighted Visual Comparison

| Criterion | Weight | V1 (`A_Medium`) | **V2 (`Hybrid Std`)** | V3 (`Hybrid Red`) |
|---|---:|---:|---:|---:|
| Overall visual quality | 20% | 3.8 | **4.7** | 4.4 |
| Pixel-art style consistency | 15% | **4.8** | 4.6 | 4.6 |
| Continuous cloud-sea impression | 20% | 3.0 | **4.8** | 4.5 |
| Settlement & exploration readability | 15% | 4.6 | **4.6** | 4.6 |
| Cloud depth and layering | 10% | 3.8 | **4.7** | 4.3 |
| Day/Night appearance | 10% | 4.2 | **4.6** | 4.5 |
| Performance & maintainability | 10% | **4.7** | 4.3 | 4.4 |
| **Weighted Total (out of 5.00)** | **100%** | **4.02** | **4.64** | **4.49** |

---

## 15. Strongest Advantage & Weakness of Each Variant

- **V1 (`A_Medium` Baseline):** *Advantage:* Simplest architecture, zero mask/shader overhead. *Weakness:* `55.87%` of the deep viewport remains flat `#0A0D14` black void.
- **V2 (`Hybrid Standard`):** *Advantage:* Eliminates black voids completely while preserving `A_Medium`'s rich foreground bank continuity (`14.54%` overlap) and crisp pixel-art silhouettes in both Day and Night. *Weakness:* Adds a `128x128` mask + `256x256` base shader layer.
- **V3 (`Hybrid Reduced`):** *Advantage:* `16.3%` fewer foreground sprites (`350` vs `418`) with clean breathing room. *Weakness:* Slightly sparser foreground bank connections (`8.79%` overlap) in the deep sea compared to V2.

---

## 16. Final Recommendation

**A. Hybrid Wins — Recommend `Variant 2 (Hybrid Standard)`** as the visual and technical direction for a future production integration milestone, pending explicit owner approval.

---

## 17. Known Limitations

- Initial full-map `_sync_full_fog_mask()` took `650.2 ms` in GDScript (`128x128` x `7x7` neighbor loop); in production this can be optimized easily via a 2-pass distance transform (`<5 ms`) or run once at world load.
- Animation (idle drift & exploration dispersal) is deferred to the next milestone (`C2`).

---

## 18. Explicit Confirmation of No Production Integration

No production scripts, scenes, shaders, or assets were modified.

## 19. Explicit Confirmation of No Staging, Commit, or Push

No `git add`, `git commit`, `git push`, `git reset`, `git clean`, or `git stash` commands were executed.
