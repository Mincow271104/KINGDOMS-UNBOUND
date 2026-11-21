# C1.9.2 — M1-R2 GPU Envelope Architecture Investigation

**Date:** 2026-11-16  
**Milestone:** C1.9.2 — M1-R2 (GPU Envelope Architecture Investigation & Isolated Prototype)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Backend / Hardware:** Godot 4.7-stable, Forward+ D3D12 (`NVIDIA GeForce RTX 3050 Ti Laptop GPU`), `1280x720`

---

## 1. Architecture Comparison

| Dimension | Option A — Optimized CPU Incremental | Option B — GPU `SubViewport` Envelope | Option C — Direct Cloud Shader Evaluation |
| --- | --- | --- | --- |
| **Where SDF Runs** | CPU GDScript (`TerrainPreviewField`) | GPU fragment shader (`envelope_gen.gdshader`) | GPU fragment shader (`cloud_envelope_opt_c.gdshader`) |
| **Update Frequency** | Only when sources change | Only when sources change (`UPDATE_ONCE`, else `UPDATE_DISABLED`) | **Every frame** across all `1280x720` pixels |
| **CPU Cost on Change** | `12.92–93.23 ms` | **`0.052–0.090 ms`** (uniform pack + `UPDATE_ONCE`) | `0.005–0.007 ms` (uniform pack) |
| **GPU Render Cost** | `0.29 ms` (cloud composite only) | `0.011–0.026 ms` (SubViewport) + `0.29 ms` (composite) | `0.295–0.501 ms` **every frame** (scales with `source_count`) |
| **Idle GPU Cost** | `0.29 ms` | `0.29 ms` (`SubViewport` = `0.000 ms`) | `0.295–0.501 ms` |
| **Source Limit** | Unlimited | `MAX_SOURCES = 32` (expandable via Data Texture) | `MAX_SOURCES = 32` |
| **Texture Memory** | `128 KB` (`1x`) / `512 KB` (`2x`) | `~64–256 KB` VRAM (`SubViewport` `RGBA8`) | `0 KB` (no envelope texture) |
| **CPU Regression Ref** | Self | Tested against `TerrainPreviewField` | Same GLSL math as Option B |

---

## 2. Prototype Implementation Details

All prototype files are isolated under `scratch/c1_9_2_m1_r2_gpu_investigation/`:
- `shaders/envelope_gen.gdshader` — Option B `SubViewport` generator evaluating up to `32` sources (`src_pos_rad[32]`, `src_dir_oval[32]`), writing `R = preview_sd`, `G = core_sd`.
- `shaders/cloud_envelope_opt_b.gdshader` — Option B cloud composite sampling `envelope_tex` (`ViewportTexture`, `filter_linear`) and `fow_explored_tex` (`128x128` `FORMAT_R8`, `filter_nearest`).
- `shaders/cloud_envelope_opt_c.gdshader` — Option C direct source evaluation in `fragment()` over `v_world_pos`.
- `run_m1_r2_investigation.gd` — Runs correctness validation, D3D12 timing benchmarks, and visual screenshot capture.

**Authoritative `FogOfWar` Separation:**
- `TerrainPreviewField` / `SubViewport` owns only visual `preview_sd` (`R`) and `core_sd` (`G`).
- `FogOfWar` remains sole authority over `UNEXPLORED`, `EXPLORED`, `VISIBLE`, and all entity/POI/wildlife/monster visibility.
- `fow_explored_tex` (`16 KB` `FORMAT_R8` for `128x128`) is owned separately and updated only when `FogOfWar` changes.

---

## 3. Performance Methodology & Results (`1280x720`, D3D12 Forward+)

Measured via `Time.get_ticks_usec()` for CPU submission and `RenderingServer.viewport_set_measure_render_time()` (`viewport_get_measured_render_time_gpu`) for `root` and `SubViewport` GPU times (median / worst over 5–6 post-warmup frames):

| Benchmark Case | Option A CPU (med/worst) | Option A GPU | Option B CPU | Option B SubVP GPU | Option B Root GPU | Option C CPU | Option C Root GPU (med/worst) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `1src_th` (`128`, `1x`) | `12.92 / 13.25 ms` | `0.29 ms` | `0.052 ms` | `0.011 ms` | `0.289 ms` | `0.006 ms` | `0.295 / 0.296 ms` |
| `3src_near` (`128`, `1x`) | `25.31 / 25.98 ms` | `0.29 ms` | `0.063 ms` | `0.012 ms` | `0.289 ms` | `0.006 ms` | `0.353 / 0.355 ms` |
| `6src_sep` (`128`, `1x`) | `39.45 / 42.16 ms` | `0.29 ms` | `0.090 ms` | `0.014 ms` | `0.290 ms` | `0.005 ms` | `0.443 / 0.444 ms` |
| `8src_ov` (`128`, `1x`) | `54.57 / 57.34 ms` | `0.29 ms` | `0.087 ms` | `0.015 ms` | `0.291 ms` | `0.006 ms` | `0.501 / 0.501 ms` |
| `1_move_sol_1x` (`6 src`) | `20.79 / 21.31 ms` | `0.29 ms` | `0.086 ms` | `0.015 ms` | `0.291 ms` | `0.006 ms` | `0.441 / 0.445 ms` |
| `4_move_sol_1x` (`6 src`) | `37.61 / 38.29 ms` | `0.29 ms` | `0.064 ms` | `0.014 ms` | `0.289 ms` | `0.006 ms` | `0.441 / 0.443 ms` |
| `1_move_sol_2x` (`128`, `2x`) | `84.81 / 93.23 ms` | `0.29 ms` | `0.078 ms` | `0.026 ms` | `0.293 ms` | `0.006 ms` | `0.445 / 0.446 ms` |
| `256map_move1_1x` (`256`, `1x`) | `19.28 / 19.92 ms` | `0.29 ms` | `0.088 ms` | `0.026 ms` | `0.291 ms` | `0.007 ms` | `0.442 / 0.443 ms` |

---

## 4. CPU / GPU Measurement Limitations
- `RenderingServer.viewport_get_measured_render_time_gpu()` reports per-viewport GPU pass timing from Godot's RenderingDevice timestamp queries; it does not break down individual draw calls inside `root` or account for driver power-state variance.
- Option B `SubViewport` GPU cost (`0.011–0.026 ms`) occurs **only** on frames where `UPDATE_ONCE` is triggered; on all other frames (`UPDATE_DISABLED`), its GPU cost is `0.000 ms`.
- Benchmarks were executed on a discrete laptop GPU (`RTX 3050 Ti`); integrated GPUs will show higher absolute shader times, which further favors Option B (evaluating `128x128` = `16,384` texels on change) over Option C (evaluating `1280x720` = `921,600` pixels every frame).

---

## 5. Correctness Comparison (Option B GPU vs CPU Reference)
Compared `SubViewport.get_texture().get_image()` against `TerrainPreviewField` CPU reference across 7 scenarios (Town Hall preview/core, overlapping, separated, soldier move, overlapping removal, map-edge, multi-soldier + Hunter):
- **`2x` (`256x256`):** `max_R = 1/255`, `max_G = 1/255`, `mean_R = 0.011–0.020`, `mean_G = 0.003–0.009`, **`gt2_R = 0`, `gt2_G = 0`** across all 65,536 texels in all 7 scenarios.
- **`1x` (`128x128`):** `max_R = 2/255` (`gt2_R = 0`), `max_G = 4/255` (`gt2_G = 1` texel at exact `dist == 0` center singularity), `mean_R = 0.010–0.017`, `mean_G = 0.003–0.011`.

---

## 6. Visual Comparison
Captured and inspected:
- `scratch/c1_9_2_m1_r2_gpu_investigation/screenshots/comparison_sheet_m1_r2.png` (9 scenarios across `0.75x`, `1.0x`, `1.5x`, `2.2x` zooms).
- `scratch/c1_9_2_m1_r2_gpu_investigation/screenshots/abc_arch_comparison.png` (Option A vs Option B vs Option C side-by-side).
- All three architectures produce visually indistinguishable, softly rounded, organically irregular cloud openings with zero rectangular artifacts or movement trails.

---

## 7. Memory, Resource Lifecycle & Godot 4.7 Compatibility
- **Memory:** Option B uses one `SubViewport` (`128x128` `RGBA8` = `64 KB` VRAM at `1x`, `256 KB` at `2x`) + one `16 KB` `FORMAT_R8` `fow_explored_tex`.
- **Lifecycle:** `SubViewport` + `ColorRect` + `ShaderMaterial` are owned by `WorldView` (or a dedicated visual helper) and freed on exit. `render_target_update_mode` stays `UPDATE_DISABLED` when idle and switches to `UPDATE_ONCE` only when sources change.
- **Godot 4.7 Compatibility:** Verified on Godot 4.7-stable D3D12 Forward+. Uniform arrays (`vec4[32]`) and `SubViewport.UPDATE_ONCE` work cleanly with zero shader compilation warnings.

---

## 8. Recommended Architecture & Remaining Risks
- **Recommendation: Option B — GPU `SubViewport` Envelope Generation** (`1x` default `128x128`, `2x` optional):
  1. **Eliminates main-thread CPU stalls:** `0.05–0.09 ms` CPU vs `20–93 ms` for Option A (`240×–1,080×` lower CPU cost).
  2. **Zero per-frame SDF scaling cost:** Unlike Option C (which evaluates `source_count` over `921,600` screen pixels every frame), Option B evaluates only `16,384` texels (`1x`) or `65,536` texels (`2x`) **only when sources change** (`0.011–0.026 ms` GPU).
  3. **Preserves CPU `TerrainPreviewField`:** `TerrainPreviewField` remains intact as the pure-GDScript source registry, dirty-state tracker, and headless unit-test/correctness reference (`--headless` has no GPU).
- **Remaining Risks:**
  - `MAX_SOURCES = 32` cap if >32 simultaneous preview sources exist (mitigated by packing into a small `32x2` `RGBAF` data texture if needed, or prioritizing active Town Hall + Hunters + nearby Soldiers).
  - Headless unit tests (`--headless`) use Godot's dummy renderer, so GPU `SubViewport` output must be tested either via CPU `TerrainPreviewField` in headless mode or windowed D3D12 visual/smoke tests.

---

## 9. Exact Files Created / Modified
- **Created (Isolated Prototype + Report):**
  - `scratch/c1_9_2_m1_r2_gpu_investigation/shaders/envelope_gen.gdshader`
  - `scratch/c1_9_2_m1_r2_gpu_investigation/shaders/cloud_envelope_opt_b.gdshader`
  - `scratch/c1_9_2_m1_r2_gpu_investigation/shaders/cloud_envelope_opt_c.gdshader`
  - `scratch/c1_9_2_m1_r2_gpu_investigation/run_m1_r2_investigation.gd`
  - `scratch/c1_9_2_m1_r2_gpu_investigation/screenshots/*` (`.png` captures + `comparison_sheet_m1_r2.png` + `abc_arch_comparison.png`)
  - `docs/reports/C1_9_2_M1_R2_GPU_ENVELOPE_INVESTIGATION.md`
- **Modified:** None. Production files (`world_view.gd`, `fog_of_war.gd`, `fog_cloud_layer.gd`, `save_manager.gd`, `terrain_preview_field.gd`, scenes, shaders, assets) remain completely untouched.

**M1-R2 Status:** Complete. Stopping for owner review and authorization before **M2**.
