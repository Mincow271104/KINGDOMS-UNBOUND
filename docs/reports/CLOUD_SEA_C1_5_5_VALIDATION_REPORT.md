# KINGDOMS UNBOUND — C1.5.5 Refined Hybrid Validation Report

**Milestone:** C1.5.5 — Cloud Sea Visual Refinement + Independent Fog Mask Optimization  
**Engine:** Godot 4.7 (`D3D12 12_0 - Forward+`, `NVIDIA GeForce RTX 3050 Ti Laptop GPU`, `TEXTURE_FILTER_NEAREST`)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Baseline HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** Isolated Prototype & Validation (Zero production edits)

---

## 1. Executive Summary

- **Visual Direction:** **V5 (`512x512` Horizontal Strata + `512x512` Secondary Wisps)** is recommended over **V4 (`512x512` Horizontal Strata)** and **V2 (`256x256` Noise Baseline)**. Both `V4` and `V5` eliminate the busy isotropic noise pattern of `V2` in favor of calm, wind-swept horizontal cloud bands that stay cleanly behind the `A_Medium` Version A foreground banks (`420` sprites, ~42–44% coverage). `V5` adds low-opacity `#1C2A46` secondary wisps sampled at `wisp_scale = 640.0` with an offset `(0.37, 0.19)` in the same `Polygon2D` shader, breaking up `512 px` horizontal periodicity with **zero extra draw calls** and **identical frame timing** (`6.946 ms` avg / `6.949 ms` median vs. `6.940 ms` / `6.934 ms` for `V2`).
- **Fog Mask Optimization:** Replacing the `7x7` per-cell neighbor loop (`_sync_full_fog_mask_ref`) with a **2-pass `PackedByteArray` Manhattan (L1) distance transform** (`_sync_full_fog_mask_fast`) reduced full-map (`128x128`) CPU mask generation from **`597.703 ms` avg (`602.157 ms` median)** to **`8.981 ms` avg (`8.743 ms` median)** — a **~66.6x** speedup (`68.9x` by median) — with `ImageTexture.update()` costing **`0.017 ms` avg**.
- **Pixel-by-Pixel Equivalence:** After matching Godot's `Image.set_pixel()` RGBA8 byte truncation for `0.42` (`107`) and `0.78` (`198`), `_sync_full_fog_mask_fast` produces **exact byte-for-byte identical `Image` buffers** (`eq_initial = true`, `eq_after_reveal = true`) before and after scout reveal.
- **Day/Night Double-Tint Confirmed:** `WorldView.sync_day_night_visuals()` sets `World/DayNightModulate.color` *and* calls `FogCloudLayer.apply_day_night_tint(cont_h)`, causing multiplicative double-tinting on `FogCloudLayer` (e.g., at `22:00` Night, `0.52 * 0.68 = 0.354 R`, `0.60 * 0.74 = 0.444 G`, `0.84 * 0.98 = 0.823 B`). Production integration must keep `FogCloudLayer` neutral (`Color(1, 1, 1, alpha)`) or use `CanvasItemMaterial`/light-mask separation so `World/DayNightModulate` serves as the single source of ambient tinting.

---

## 2. Scope & Preservation Compliance

| Check | Status | Details |
| :--- | :--- | :--- |
| **Production Code / Scenes / Assets** | **Preserved (0 edits)** | No files modified under `scripts/`, `scenes/`, `assets/`, or `addons/`. |
| **Prototype Location** | **Isolated in Scratch** | All scripts, textures, raw JSON, and screenshots reside in `<AppDataDir>/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_5_refined_hybrid/`. |
| **Git State** | **Clean vs. Baseline** | Only `docs/reports/CLOUD_SEA_C1_5_5_VALIDATION_REPORT.md` added on top of the recorded `406`-entry pre-C1.5.5 baseline; no `git add`, `commit`, `push`, `reset`, `clean`, or `stash` performed. |

---

## 3. Prototype Architecture & Files Created

All C1.5.5 artifacts live in `scratch/c1_5_5_refined_hybrid/`:
- `generate_v4_v5_textures.py` — Generates seamless pixel-art `2x2`-blocked `512x512` textures using the C1.5.3 dark-fantasy palette (`#0B101B`–`#1C2A46`).
- `assets/cloud_sea_base_v4_512.png` — `512x512` tileable horizontal cloud-band strata texture (3 undulating bands, Bayer dithering, crisp `2x2` pixel blocks).
- `assets/cloud_sea_base_v5_wisps_512.png` — `512x512` tileable `#1C2A46` horizontal wind-swept secondary wisps (`alpha = 55, 105`) for multi-scale overlay.
- `run_c1_5_5_validation.gd` — Standalone Godot 4.7 validation runner executing visual captures across 3 variants × 4 views × 4 times of day + scout reveal, Part C mask benchmark, and Part E 60-frame timing.
- `make_c1_5_5_sheets.py` — Generates side-by-side `V2 | V4 | V5` comparison sheets (`comp_*.png`) in `screenshots/`.
- `raw_c1_5_5.json` — Raw JSON output of frame timings, mask benchmark stats, equivalence flags, and Day/Night ambient RGB values.

---

## 4. CloudSeaBase V4 & V5 Design Comparison

| Variant | Base Texture(s) | Sampling & Shader Logic | Visual Character |
| :--- | :--- | :--- | :--- |
| **V2_Baseline** | `cloud_sea_base_256.png` (`256x256`) | Single `base_tex` sample (`tex_scale = 256.0`), `4x4` Bayer dither on `fog_mask` (`0.02..0.98`), `base_alpha = 0.96`. | Textured isotropic dark-blue mist; slightly busy at `2.25x` close-up and `256 px` repeat period. |
| **V4_Strata** | `cloud_sea_base_v4_512.png` (`512x512`) | Single `base_tex` sample (`tex_scale = 512.0`), same Bayer dither & `fog_mask` UV mapping (`u_grid, v_grid`). | Calm, broader horizontal layered cloud strata; cleaner depth separation behind `A_Medium` foreground banks. |
| **V5_MultiScale** | `cloud_sea_base_v4_512.png` (`512x512`) + `cloud_sea_base_v5_wisps_512.png` (`512x512`) | Same shader + `mix(col.rgb, wcol.rgb, wcol.a * 0.85)` with `wisp_tex` sampled at `(v_world_pos / 640.0) + vec2(0.37, 0.19)`. | Preserves `V4`'s calm horizontal strata while breaking up `512 px` horizontal repetition with subtle wind-swept mid-tone wisps; **no extra draw calls**. |

---

## 5. Visual Comparison & Acceptance Matrix

Inspected side-by-side comparison sheets across:
- **View 1 (Settlement, `1.5x`, `12:00` Day):** `comp_v1_settlement_day.png`
- **View 2 (Deep Cloud Sea, `1.5x`, Day / Dawn `06:00` / Dusk `18:30` / Night `22:00`):** `comp_v2_deep_day.png`, `comp_v2_deep_dawn.png`, `comp_v2_deep_dusk.png`, `comp_v2_deep_night.png`
- **View 3 (Close-Up, `2.25x`, `12:00` Day):** `comp_v3_closeup_day.png`
- **View 4 (Irregular Scout Pocket Before & After Reveal, `1.5x`, `12:00` Day):** `comp_v4_scout_before.png`, `comp_v4_scout_after.png`

### Visual Acceptance Matrix (1 = Poor, 5 = Excellent)

| Criterion | V2_Baseline | V4_Strata | V5_MultiScale | Notes |
| :--- | :---: | :---: | :---: | :--- |
| **1. Foreground Dominance (`A_Medium`, 420 sprites)** | 4.5 | **5.0** | **5.0** | Calmer horizontal floor in `V4`/`V5` makes `main_cloud_01..03` banks pop more cleanly. |
| **2. Horizon / Cloud-Sea Continuity** | 3.5 | 4.5 | **5.0** | `V4` reads as horizontal strata; `V5`'s `640 px` wisp layer removes residual `512 px` regularity. |
| **3. Pixel-Art Crispness (`2.25x` Close-Up)** | 4.0 | **5.0** | **5.0** | Nearest-neighbor `2x2` blocks + `4x4` Bayer dither hold crisp silhouettes with zero blur. |
| **4. Seam & Tiling Concealment** | 3.5 | 4.0 | **4.5** | `V5` dual-period (`512` + `640` with `(0.37, 0.19)` offset) prevents visible grid repeats across deep fog. |
| **5. A2 Frontier & Reveal Edge Cleanliness** | 4.5 | **5.0** | **5.0** | Bayer-dithered `fog_mask` transition around settlement and scout pocket reads cleanly before & after reveal. |
| **6. Day / Dawn / Dusk Readability** | 4.5 | **5.0** | **5.0** | Warm Dawn (`06:00`) and Dusk (`18:30`) preserve foreground volume and background strata contrast. |
| **7. Night (`22:00`) Legibility** | 4.0 | 4.5 | **4.5** | Under single `DayNightModulate` (`0.52, 0.60, 0.84`), both strata and banks remain legible without black collapse. |
| **8. Visual Restraint (Low Clutter)** | 3.5 | **5.0** | **4.8** | `V2` isotropic noise feels busiest; `V4` is cleanest, `V5` adds just enough variation without clutter. |
| **Mean Score** | **4.00** | **4.75** | **4.85** | **V5_MultiScale** ranks highest overall. |

---

## 6. Fog Mask Optimization Results (Part C)

Benchmark executed on the `128x128` (`16,384`-cell) `FogOfWar` grid after 5 warm-up iterations and 30 measured iterations (`raw_c1_5_5.json`):

| Metric | Reference `7x7` (`_sync_full_fog_mask_ref`) | 2-Pass `PackedByteArray` (`_sync_full_fog_mask_fast`) | Speedup |
| :--- | :---: | :---: | :---: |
| **Average (ms)** | `597.703 ms` | **`8.981 ms`** | **66.55x** |
| **Median (ms)** | `602.157 ms` | **`8.743 ms`** | **68.87x** |
| **P95 (ms)** | `654.987 ms` | **`11.097 ms`** | **59.02x** |
| **Worst (ms)** | `664.995 ms` | **`13.258 ms`** | **50.16x** |
| **GPU Texture Upload (`_fog_mask_tex.update`)** | — | **`0.017 ms` avg / `0.017 ms` med / `0.022 ms` p95 & worst** | Negligible |
| **Initial Byte Equivalence (`eq_initial`)** | — | **`true`** (100% identical `PackedByteArray`) | Exact |
| **Post-Reveal Equivalence (`eq_after_reveal`)** | — | **`true`** (100% identical `PackedByteArray`) | Exact |

### Implementation Note Discovered During Verification
Godot's `Image.set_pixel(x, y, Color(v, v, v, 1.0))` truncates `float(0.78 * 255.0) = 198.9` to byte **`198`**, whereas `round(0.78 * 255.0)` / `Color.r8` produces **`199`**. Encoding the `PackedByteArray` LUT via `Image.set_pixel` on a `2x1` scratch `Image` (producing `[0, 0, 107, 198, 255]`) guarantees **exact byte-for-byte parity** with the reference implementation.

---

## 7. Day/Night Tint Investigation (Part D)

Code inspection of `scripts/world/world_view.gd` (`4737–4747`) and `scripts/world/fog_cloud_layer.gd` (`124–144`) confirms **double-tinting occurs in production**:

1. `WorldView.sync_day_night_visuals()` assigns `World/DayNightModulate.color = get_ambient_color_for_time(cont_h)`:
   - `06:00` Dawn: `(0.970, 0.835, 0.720)`
   - `18:30` Dusk: `(0.950, 0.660, 0.480)`
   - `22:00` Night: `(0.520, 0.600, 0.840)`
2. Immediately afterward, `WorldView` calls `fog_cloud_layer.apply_day_night_tint(cont_h)`, which sets `FogCloudLayer.modulate`:
   - Day (`8.0..17.5`): `(1.00, 1.00, 1.00, 0.94)`
   - Dawn (`5.0..7.0` target): `(0.95, 0.96, 1.04, 0.93)`
   - Dusk (`17.5..19.0` target): `(0.84, 0.80, 1.08, 0.94)`
   - Night (`20.5..5.0`): `(0.68, 0.74, 0.98, 0.96)`
3. Because `FogCloudLayer` is inside the `World` canvas affected by `World/DayNightModulate`, the two colors **multiply**:
   - **Night (`22:00`) effective multiplier:** `0.52 * 0.68 = 0.354 R`, `0.60 * 0.74 = 0.444 G`, `0.84 * 0.98 = 0.823 B` (excessive darkening and blue crush).
   - **Dusk (`18:30`) effective multiplier:** `0.95 * 0.84 = 0.798 R`, `0.66 * 0.80 = 0.528 G`, `0.48 * 1.08 = 0.518 B` (cancels warm dusk lighting into murky grey-purple).

**Safe Resolution:** Let `World/DayNightModulate` serve as the **single tint authority** during production integration and keep `FogCloudLayer` (and `CloudSeaBase`) at neutral RGB `(1.0, 1.0, 1.0, alpha)`. This was validated across all 4 times of day in C1.5.5 (`comp_v2_deep_*`).

---

## 8. Frame-Time Performance Comparison (Part E)

Measured on View 2 (Deep Cloud Sea, `1.5x` zoom, `12:00` Day), 30 warm-up frames + 60 timed frames (`raw_c1_5_5.json`):

| Variant | Avg (ms) | Median (ms) | P95 (ms) | Worst (ms) | Delta vs. V2 (Median) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **V2_Baseline** | `6.940` | `6.934` | `7.207` | `7.420` | Baseline |
| **V4_Strata** | `6.944` | `6.941` | `7.038` | `7.570` | `+0.007 ms` (~0.1%) |
| **V5_MultiScale** | `6.946` | `6.949` | `7.132` | `7.278` | `+0.015 ms` (~0.2%) |

All three variants stay well within a `60 FPS` (`16.67 ms`) budget with essentially identical GPU cost (`~6.94 ms`, dominated by viewport sync / normal rendering rather than the single-quad `CloudSeaBase` shader).

---

## 9. Risks & Edge Cases

1. **Incremental vs. Full Mask Sync:** At `8.98 ms` average for a full `128x128` rebuild, even a full-map fog reset fits inside a single frame, whereas `597.70 ms` in the reference `7x7` loop caused a multi-frame hitch. Incremental dirty-rect updates can still be layered on top later if maps scale to `256x256+`.
2. **Dusk / Night Contrast Tuning:** Under single `DayNightModulate`, `V5` remains legible at `22:00` Night, though final production tuning should verify visibility against player UI banners and minimap edges in live gameplay.

---

## 10. Explicit Answers to C1.5.5 Validation Questions

1. **Does `V4` (`512x512` horizontal strata) clearly improve over `V2` (`256x256` noise) in deep fog, settlement view, and close-up?**  
   **Yes.** `V4` replaces `V2`'s noisy isotropic texture with calm, horizontal cloud strata that read as a continuous cloud sea and improve foreground bank separation across all three views.
2. **Does `V5` (secondary wisps) add meaningful visual depth or break up `512 px` repetition without adding clutter?**  
   **Yes.** At `wisp_scale = 640.0` and low alpha (`55, 105` mixed at `0.85`), `V5` breaks up `512 px` horizontal periodicity without competing with the `A_Medium` foreground sprites.
3. **Which variant (`V2`, `V4`, or `V5`) should become the production `CloudSeaBase` design?**  
   **`V5_MultiScale`** (`cloud_sea_base_v4_512.png` + `cloud_sea_base_v5_wisps_512.png` in a single `Polygon2D` shader pass).
4. **Is the 2-pass `PackedByteArray` distance transform pixel-identical to the reference `7x7` loop?**  
   **Yes.** Both `eq_initial` and `eq_after_reveal` returned **`true`** after matching `Image.set_pixel()`'s RGBA8 truncation (`[0, 0, 107, 198, 255]`).
5. **What is the measured speedup of `_sync_full_fog_mask_fast` vs. `_sync_full_fog_mask_ref`?**  
   **`66.55x` average speedup** (`597.703 ms` -> `8.981 ms`) and **`68.87x` median speedup** (`602.157 ms` -> `8.743 ms`), plus `0.017 ms` avg texture upload.
6. **Does double-tinting occur between `World/DayNightModulate` and `FogCloudLayer.apply_day_night_tint()`, and what is the recommended fix?**  
   **Yes**, `FogCloudLayer.modulate` multiplies on top of `World/DayNightModulate.color` (crushing Night to `0.354 R` and muting Dusk). **Recommended fix:** remove or neutralize `apply_day_night_tint()` RGB modulation so `World/DayNightModulate` is the single ambient tint source.
7. **Is C1.5.5 ready to proceed to an explicit Production Integration phase (C1.6)?**  
   **Yes**, pending owner sign-off on `V5_MultiScale` and authorization to modify production files (`fog_cloud_layer.gd`, `world_view.gd`, and cloud-sea assets).

---

## 11. Recommended Production Architecture (For C1.6, Pending Authorization)

- **Layer Order:** `CloudSeaBase` (`Polygon2D` with `V5_MultiScale` shader, `z_index` beneath `FogCloudLayer` banks) -> `A_Medium` `FogCloudLayer` chunked foreground sprites (`main_cloud_01..03.png`).
- **Mask Pipeline:** Use `_sync_full_fog_mask_fast` (2-pass `PackedByteArray` L1 transform + `Image.create_from_data` + `ImageTexture.update`) for initial sync and full refreshes.
- **Day/Night:** Single tint via `World/DayNightModulate`; keep `CloudSeaBase` and `FogCloudLayer` modulate RGB at `(1.0, 1.0, 1.0)`.

---

## 12. Visual Artifact Index

All comparison sheets in `C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_5_refined_hybrid/screenshots/`:
- `comp_v1_settlement_day.png`
- `comp_v2_deep_day.png`
- `comp_v2_deep_dawn.png`
- `comp_v2_deep_dusk.png`
- `comp_v2_deep_night.png`
- `comp_v3_closeup_day.png`
- `comp_v4_scout_before.png`
- `comp_v4_scout_after.png`
- `comp_v5_all_tod.png`
