# C1.9.2 — M1-R1 Performance Remediation Report

**Date:** 2026-11-16  
**Milestone:** C1.9.2 — M1-R1 (`TerrainPreviewField` Performance Investigation & Incremental Optimization)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Pre-existing Working Tree Status:** Preserved untouched (`424` `git status --short` entries including M1/M1-R1 deliverables)

---

## 1. Root Cause of the Original Performance Problem

Instrumentation of the M1 baseline (`get_last_profile_stats()`) proved three exact bottlenecks:

1. **100% Dirty-Rect Coverage on `128x128` Maps:**
   - M1 projected a screen-aligned iso AABB (`margin_y = r_max * 1.25 + 300 + 202.5 = ~708–890 px`) onto the 45°-rotated `(u_grid, v_grid)` grid.
   - Because isometric axes are rotated 45°, projecting AABB corners inflated the dirty bounding box by `~1.414×` (`+/- 70` tiles -> `141x141` tiles), clamping every incremental update on a `128x128` map to `(0, 0, 128, 128)` (`100.0%` of texels).
   - Consequently, `move_inc` at `2x` evaluated all `6` sources at all `65,536` texels (`393,216` SD evaluations, `376.52 ms`).
2. **Redundant Per-Texel Work:**
   - Every texel inside the dirty rect evaluated all candidate sources in the rect even when a texel lay outside the changed source's influence ellipse or outside a candidate source's `reach_y`.
3. **Texture Upload Was Negligible:**
   - `Image.set_data()` + `ImageTexture.update()` measured `0.006–0.010 ms` across all runs — `99.99%` of cost was CPU GDScript SDF evaluation (`eval_ms`).

---

## 2. Optimization Details (Zero Semantic / Mathematical Change)

Implemented in [terrain_preview_field.gd](file:///e:/KINGDOMS%20UNBOUND/kingdoms-unbound/scripts/world/terrain_preview_field.gd):
1. **Exact Elliptical `(u, v)` Dirty-Rect Projection:** Replaced AABB corner projection with exact rotated-ellipse bounds `half_uv = sqrt((reach_y * ox / 32)^2 + (reach_y / 16)^2)`, cutting bounding-box area by ~47%.
2. **Coalesced Diff Against Committed State (`_committed_sources`):** Repeated `update_source()` calls in a single tick only dirty `(committed -> final)` instead of intermediate positions.
3. **Changed-Ellipse Texel Filtering:** `_evaluate_rect_filtered()` skips texels inside the merged bounding box that lie outside every changed source's influence ellipse.
4. **Per-Source `reach_sq` Early-Out & Tight `LOBE_MAX`:** Precomputes `reach_y = max_r * lobe_max + 300.0 + 1.5 * 135.0` (`lobe_max = 1.08` for non-directional, `1.19` for `HUNTER_SCOUT`). Any source with `d2 > reach_sq` is skipped before `sqrt` and Chebyshev trig (mathematically lossless because `dp > 502.5` cannot alter `_smin(..., 135.0)` for `p_sd <= 300.0` or pull `p_sd > 300.0` below `300.0`).
5. **Linear Iso-Coordinate Stepping:** Steps `iso_x` and `iso_y` linearly across `tx` instead of recomputing from `(u_grid, v_grid)` per texel.
6. **1× Default Resolution:** Changed `configure(..., res_scale = 1)` default to `1` while keeping `2` supported.

---

## 3. Before / After Benchmarks & Dirty-Rectangle Coverage

### 3.1 M1 Baseline (Before Optimization, Single-Run Profiled)
- **`1x` (`128x128`, `128 KB`):**
  - `inc_3`: `60.19 ms` | `16,384` texels (`100.0%`), `49,152` SD evals, `upload = 0.009 ms`
  - `inc_8`: `106.87 ms` | `16,384` texels (`100.0%`), `131,072` SD evals, `upload = 0.007 ms`
  - `move_inc`: `88.18 ms` | `16,384` texels (`100.0%`), `98,304` SD evals, `upload = 0.009 ms`
  - `remove_inc`: `83.09 ms` | `16,384` texels (`100.0%`), `81,920` SD evals, `upload = 0.008 ms`
- **`2x` (`256x256`, `512 KB`):**
  - `inc_3`: `239.98 ms` | `65,536` texels (`100.0%`), `196,608` SD evals, `upload = 0.008 ms`
  - `inc_8`: `421.00 ms` | `65,536` texels (`100.0%`), `524,288` SD evals, `upload = 0.008 ms`
  - `move_inc`: `376.52 ms` | `65,536` texels (`100.0%`), `393,216` SD evals, `upload = 0.009 ms`
  - `remove_inc`: `311.89 ms` | `65,536` texels (`100.0%`), `327,680` SD evals, `upload = 0.008 ms`

### 3.2 M1-R1 Optimized (Warm-Up + 5 Iterations, Median & Worst)
| Map & Resolution | Scenario | Median (ms) | Worst (ms) | Dirty Texels | Texture % | SD Evals | Memory |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `128x128` (`1x`) | `full_1src` | `28.13` | `28.92` | `16,384` | `100.0%` | `10,145` | `128 KB` |
| `128x128` (`1x`) | `full_3src` | `44.26` | `46.26` | `16,384` | `100.0%` | — | `128 KB` |
| `128x128` (`1x`) | `inc_3src` | `33.81` | `36.40` | `8,757` | `53.4%` | `22,155` | `128 KB` |
| `128x128` (`1x`) | `full_8ov` | `72.51` | `73.96` | `16,384` | `100.0%` | — | `128 KB` |
| `128x128` (`1x`) | `full_6sep` | `53.62` | `57.59` | `16,384` | `100.0%` | — | `128 KB` |
| `128x128` (`1x`) | `move_1sol` | `29.85` | `31.67` | `7,065` | `43.1%` | `21,040` | `128 KB` |
| `128x128` (`1x`) | `coal_4sol` | `48.28` | `51.42` | `10,049` | `61.3%` | `25,058` | `128 KB` |
| `128x128` (`2x`) | `full_1src` | `126.95` | `129.97` | `65,536` | `100.0%` | `40,610` | `512 KB` |
| `128x128` (`2x`) | `full_3src` | `167.77` | `179.88` | `65,536` | `100.0%` | — | `512 KB` |
| `128x128` (`2x`) | `inc_3src` | `119.22` | `134.23` | `34,984` | `53.4%` | `88,522` | `512 KB` |
| `128x128` (`2x`) | `full_8ov` | `300.80` | `319.91` | `65,536` | `100.0%` | — | `512 KB` |
| `128x128` (`2x`) | `full_6sep` | `203.74` | `218.66` | `65,536` | `100.0%` | — | `512 KB` |
| `128x128` (`2x`) | `move_1sol` | `117.61` | `129.03` | `28,222` | `43.1%` | `84,014` | `512 KB` |
| `128x128` (`2x`) | `coal_4sol` | `199.32` | `208.55` | `40,172` | `61.3%` | `100,110` | `512 KB` |
| `256x256` (`1x`) | `full_1` | `35.90` | `40.34` | `65,536` | `100.0%` | — | `512 KB` |
| `256x256` (`1x`) | `inc_move` | `14.12` | `14.86` | `6,925` | `10.6%` | — | `512 KB` |
| `256x256` (`2x`) | `full_1` | `150.54` | `154.62` | `262,144` | `100.0%` | — | `2048 KB` |
| `256x256` (`2x`) | `inc_move` | `56.28` | `60.87` | `27,662` | `10.6%` | — | `2048 KB` |

*(Note: `move_1sol` improved `2.95×` at `1x` (`88.18 ms -> 29.85 ms`) and `3.20×` at `2x` (`376.52 ms -> 117.61 ms`); SD evaluations dropped `4.67×` from `393,216` to `84,014`.)*

---

## 4. Correctness & Equivalence Test Results

Command: `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s "res://scripts/test/test_terrain_preview_field.gd"`
- **Result:** `PASS: test_terrain_preview_field.gd (21 assertions passed, 0 failed)` (`exit=0`).
- Verified byte-for-byte `Image.get_data()` equivalence against a clean `rebuild_full()` for: source registration, soldier movement, repeated movement before flush, coalesced multi-soldier movement, overlapping source removal, Town Hall expansion, and map-edge sources at both `1x` and `2x`.
- Verified deterministic output across independent instances and zero mutation of `FogOfWar`.

---

## 5. 1× vs 2× Recommendation & Remaining Limitations

- **Honest Assessment of Incremental Bounds on `128x128`:** Even with exact elliptical culling and lossless `reach_sq` early-out, a single soldier's `165 px` preview + `300 px` SDF clamp + `202.5 px` smooth-min margin (`reach_y = 680.7 px` = `~49.4` tiles radius) inherently covers **`43.1%`** of a `128x128` map (`10.6%` of a `256x256` map). Thus, on `128x128`, CPU GDScript evaluation of a moving soldier still takes `~29.85 ms` at `1x` and `~117.61 ms` at `2x`.
- **Recommendation:**
  1. Use **`1x` (`128x128`, `128 KB`)** as the default production candidate (`4×` faster, `4×` less memory, and `cloud_sea_envelope.gdshader` already applies `filter_linear` bilinear interpolation). Keep `2x` optional for visual comparison in M2.
  2. In M2, **throttle/coalesce moving-unit envelope updates** (e.g. max once per `0.25–0.5s` or `>= 2` tiles moved), OR move envelope SDF evaluation to a **GPU `SubViewport` fragment shader** (`< 0.5 ms` per frame) if per-frame smoothness is desired.
- **Data Separation:** `TerrainPreviewField` remains visual-only (`preview_sd` `R`, `core_sd` `G`, read-only `FogOfWar.is_explored` `B`); `FogOfWar` remains sole authority over `EXPLORED`, `VISIBLE`, and entity visibility.

---

## 6. Exact Files Modified & Untouched Production Confirmation
- **Modified:**
  - `scripts/world/terrain_preview_field.gd`
  - `scripts/test/test_terrain_preview_field.gd`
- **Created:**
  - `docs/reports/C1_9_2_M1_R1_PERFORMANCE_REMEDIATION_REPORT.md`
- **Untouched Production Files Confirmed:** `scripts/world/world_view.gd`, `scripts/world/fog_of_war.gd`, `scripts/world/fog_cloud_layer.gd`, `scripts/persistence/save_manager.gd`, existing scenes, shaders, and cloud assets were not modified.

**M1-R1 Status:** Complete. Stopping for owner review before **M2**.
