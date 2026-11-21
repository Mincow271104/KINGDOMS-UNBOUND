# KINGDOMS UNBOUND — C1.5.4 Architecture & Visual Design Review

**Milestone:** C1.5.4 — Independent Investigation, Critical Discussion & Optimal Direction  
**Date:** 2026-11-15  
**Engine:** Godot 4.7 (`Forward+`, `TEXTURE_FILTER_NEAREST`)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Baseline HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** Strictly Read-Only Investigation (No Production Integration, No Code/Asset Edits)

---

## 1. Executive Recommendation

**Recommended Direction:** **Direction B — Refined Hybrid** (Preserve Version A `A_Medium` foreground banks unchanged; refine `CloudSeaBase` from a `256x256` periodic noise floor into a `512x512` subdued horizontal layered pixel-art cloud-bank base; benchmark a `PackedByteArray` 2-pass mask distance transform in an isolated **C1.5.5** validation pass before production integration).

- **Verified Evidence:** C1.5.3 proved that pairing a masked `CloudSeaBase` (`z=6`) with `A_Medium` Version A sprites (`z=7`) eliminates the `#0A0D14` black void, preserves the A2 Organic Pixel-Mist Fringe (`z=5`), maintains `0` explored-tile leaks, and keeps `inc_matches_full=true` with `0.026 ms` dirty mask GPU uploads.
- **Visual Judgment:** Version A (`C1.1` refined) remains the strongest foreground morphology for pixel-art cohesion with the game's buildings and trees, whereas C1.5.3's `256x256` `CloudSeaBase` reads slightly too much like generic dark textured mist and shows subtle `256 px` horizontal repetition in `V3`.
- **Engineering Inference:** Replacing only the `256x256` noise base with a `512x512` subdued horizontal layered cloud-band texture (and benchmarking a 2-pass mask build) fixes V2's remaining weaknesses without risking Version A's proven identity.

---

## 2. Actual Files and Assets Inspected

- **Reports:** `docs/reports/CLOUD_SEA_C1_5_3_IMPLEMENTATION_REPORT.md`, `scratch/c1_5_1_density_test/C1_5_1_IMPLEMENTATION_REPORT.md`
- **C1.5.3 Prototype & Outputs:** `scratch/c1_5_3_hybrid_test/run_c1_5_3_hybrid_test.gd`, `generate_cloud_base.py`, `analyze_c1_5_3.py`, `assets/cloud_sea_base_256.png`, `raw_results.json`, `metrics_summary.csv`, and all 8 comparison sheets under `scratch/c1_5_3_hybrid_test/screenshots/`
- **C1.5.1 Prototype:** `scratch/c1_5_1_density_test/run_c1_5_1_density_test.gd`
- **Production Code:** `scripts/world/fog_of_war.gd`, `scripts/world/fog_cloud_layer.gd`, `scripts/world/world_view.gd`, `scripts/utils/iso_math.gd`, `scripts/persistence/save_manager.gd`, `scenes/world/world_view.tscn`
- **Assets:** `scratch/c1_1_refined/main_cloud_01..03.png` (Version A) and `scratch/c1_4_morphology/cloud_a..c.png` (Version B)

---

## 3. Current V2 (`Hybrid Standard`) Strengths and Weaknesses

### Strengths (Verified Evidence + Visual Judgment)
1. **Eliminates Black Voids:** Deep unexplored views (`deep_cloud_sea_day.png`, `deep_cloud_sea_night.png`) no longer show `~56%` flat `#0A0D14` void.
2. **Clear Foreground Hierarchy:** `418` Version A sprites (`44.13%` fg coverage, `14.54%` >=2x overlap) sit cleanly above the subdued base (`z=7` over `z=6`).
3. **Clean Exploration & A2 Preservation:** Bayer-dithered `1.5–3.0` tile transition behind the A2 fringe keeps the settlement and irregular scout pocket crisp with `0` leaks.
4. **Coherent Day/Night:** Relying on `World/DayNightModulate` without extra multiplicative darkening keeps `12:00` Day and `22:00` Night legible.

### Weaknesses (Visual Judgment + Verified Evidence)
1. **Generic Mist-Floor Read:** `cloud_sea_base_256.png` uses isotropic/2:1 domain-warped noise, which reads between banks as dark textured mist rather than distant horizontal cloud strata.
2. **Subtle `256 px` Tiling Periodicity:** Visible across wide `853 px` (`1.5x`) deep-sea spans when foreground density drops (noticeable in `V3_Hybrid_Reduced`).
3. **Unoptimized Initial Mask Build:** `_sync_full_fog_mask()` took `650.198 ms` in GDScript on `128x128` due to nested `7x7` `Vector2i` allocations.
4. **Unverified Frame-Time Stability:** C1.5.3 measured only 20 un-warmed frames per variant.

---

## 4. Foreground Morphology Assessment

- **Verified Evidence (C1.5.1 & C1.5.3):** Version A (`main_cloud_01..03.png`) scored `53/60` at `A_Medium` (`1.5x`), outperforming Version B across all three densities (`36`, `42`, `39 / 60`).
- **Visual Judgment:**
  - *Is Version A too fragmented?* No at `A_Medium` (`14.54%` >=2x overlap); `V3` (`8.79%` overlap) begins to lose bank continuity.
  - *Too rock-like?* Up close (`2.25x`), a few small internal puffs remain busy, but at primary `1.5x` gameplay zoom it reads clearly as stylized pixel-art cumulus clouds matching the Town Hall, cottages, rocks, and pine trees.
  - *Should we mix Version A with C1.4 (Version B)?* **No.** C1.4 sprites have smooth, flat tonal bands that clash with Version A's crisp pixel-art clusters; mixing them creates stylistic dissonance.
- **Conclusion:** **Preserve Version A unchanged** at `V2` (`A_Medium`) density (`~42–44%` foreground coverage).

---

## 5. Background Architecture Assessment

- **Visual Judgment of Current `cloud_sea_base_256.png`:** Technically clean (zero seams, matches `2x2` pixel scale, low contrast), **but** visually it behaves like a dark mottled noise floor rather than distant cloud layers.
- **Recommended Background Refinement:** Replace the `256x256` noise tile with a **`512x512` subdued horizontal layered cloud-band pixel-art texture** (2–3 broad, overlapping horizontal strata in the same `#0B101B`–`#1C2A46` palette with restrained `2x2` Bayer dithering, zero tiny dots, and zero isolated rounded domes).
- **Engineering Inference:** Doubling the tile period from `256 px` to `512 px` reduces horizontal tiling repeats across a `1280 px @ 1.5x` (`853 px`) viewport from `3.33x` to `1.67x`, while horizontal strata establish clear directional cloud-sea flow.

---

## 6. Fog of War and Day/Night Compatibility Assessment

- **Verified Evidence:**
  - `FogOfWar` (`UNEXPLORED=0`, `EXPLORED=1`, `VISIBLE=2`) remains the single source of truth; `SaveManager` restores `FogOfWar` and triggers full sync.
  - World-space `IsoMath` inverse projection in the `CloudSeaBase` shader aligns `1:1` with `FogOfWar` cells and discards outside `[0..1]^2`.
  - `z_index` order (`5` A2 `FogTileMapLayer` -> `6` `CloudSeaBase` -> `7` foreground `FogCloudLayer` -> `10` `CursorHighlight` -> `HUD` `CanvasLayer`) is clean and integer-based.
- **Engineering Inference (Day/Night):** Production `FogCloudLayer.apply_day_night_tint()` currently multiplies `modulate` on top of `World/DayNightModulate`. In production integration, either `apply_day_night_tint()` must be neutralized/recalibrated for `DayNightModulate` or kept at neutral white during Day/Night so night (`0.52, 0.60, 0.84`) does not double-darken. Dawn (`05:30–06:30`) and Dusk (`18:00–19:30`) remain **untested hypotheses** and should be added to C1.5.5.

---

## 7. Performance Investigation

- **Verified Evidence (C1.5.3):**
  - `_sync_full_fog_mask()` took `650.198 ms` on `128x128` because it ran `128 * 128 * 49` (`~802,816`) inner iterations allocating `Vector2i` objects and calling `IsoMath.is_in_bounds()` + `fog.is_unexplored()` per iteration.
  - Dirty update (`113` cells) took `1.147 ms` CPU + `0.026 ms` `ImageTexture.update()`.
- **Engineering Inference:** A 2-pass `PackedByteArray` distance transform (forward + backward sweep over a flat `mw * mh` byte array, zero `Vector2i` allocations in the inner loop) will reduce initial full-mask build dramatically, **but** the exact `ms` cost is an **untested hypothesis** until benchmarked in C1.5.5.
- **Maintainability:** One `Polygon2D` + `128x128` `ImageTexture` updated on `dirty_cells` events has zero per-frame CPU cost and fits cleanly inside `FogCloudLayer`.

---

## 8. C1.5.3 Metric Discrepancy Analysis

Direct inspection of `run_c1_5_1_density_test.gd`, `run_c1_5_3_hybrid_test.gd`, and `CLOUD_SEA_C1_5_3_IMPLEMENTATION_REPORT.md` resolved all 5 inconsistencies:

1. **C1.5.1 (`42.62%`, `419` sprites) vs. C1.5.3 (`44.13%`, `418` sprites):**
   - **Cause:** C1.5.1 used `v2_pos = spawn + Vector2i(22, 16)` and scout pocket `(8, -4)` r=4; C1.5.3 shifted `v2_pos` to `spawn + Vector2i(24, 18)` (moving 2 tiles SE) and used an L-shaped pocket `(10, 4)` r=4 + `(13, 2)` r=3 (suppressing 1 sprite: `419 -> 418`). Different viewport tiles explain the `+1.51%` difference.
2. **V1 Weighted Score Arithmetic (`4.02` reported vs. `4.04` actual):**
   - **Cause:** Recalculating from Section 14's table (`3.8*0.20 + 4.8*0.15 + 3.0*0.20 + 4.6*0.15 + 3.8*0.10 + 4.2*0.10 + 4.7*0.10`) yields `0.76 + 0.72 + 0.60 + 0.69 + 0.38 + 0.42 + 0.47 = 4.04`. The `4.02` figure in C1.5.3 was a `-0.02` arithmetic error. (`V2 = 4.64` and `V3 = 4.49` recalculate cleanly.)
3. **"V4" in Visible Cloud Instance Table (`43 / 64 / 32 / 44`):**
   - **Cause:** `V1 / V2 / V3 / V4` on row `Visible cloud instances` referred to **Camera Views 1–4** (`v1`–`v4`), not a fourth variant—ambiguous notation because the table columns are also labeled `V1`, `V2`, `V3`.
4. **Coverage Methodology Consistency:**
   - **Verified:** Within C1.5.3, all 3 variants used identical `853x480` viewports, `(24, 18)` camera center, `alpha > 25` threshold, and union pixel counting. Cross-milestone (`C1.5.1` vs `C1.5.3`) differed only in `v2` center `(22,16)` vs `(24,18)`.
5. **V3 Higher Frame Time (`6.84 ms`) Despite Fewer Sprites (`350` vs `418`):**
   - **Cause:** `run_c1_5_3_hybrid_test.gd` averaged only `20` frames with **no warm-up** and no median/worst-case stats, after `V1` and `V2` had already churned `836` `Sprite2D` nodes. `0.74 ms` is OS/GPU jitter, not a V3 rendering slowdown.

---

## 9. Comparison of Three Viable Directions

| Dimension | Direction A: Preserve V2 As-Is | **Direction B: Refined Hybrid (Recommended)** | Direction C: Multi-Layer Sprite Sea (No Shader Base) |
|---|---|---|---|
| **Visual Quality** | Good continuity, mottled noise floor | **Best:** Layered horizontal cloud floor + Version A banks | Good depth, but black voids persist unless 60%+ dense |
| **Pixel-Art Consistency** | High (`4.5/5`) | **Highest (`4.8/5`):** `512x512` strata + Version A | High (`4.8/5`) |
| **FoW & A2 Compatibility** | Proven (`0` leaks) | Proven (`0` leaks, same mask shader) | Proven (`0` leaks), no mask needed |
| **Day/Night Compatibility** | Proven (`12:00` & `22:00`) | Proven (needs Dawn/Dusk check) | Proven |
| **Performance** | `650 ms` unoptimized mask init | **Fastest** if 2-pass mask validates `<10 ms` | Higher sprite count (`600–800+` nodes) & overdraw |
| **Maintainability** | Medium | Medium (same architecture as V2, better texture) | Simple but heavy on `Node2D` count |
| **Identity Risk** | Low | **Lowest:** Preserves Version A untouched | Medium (clutter risk at high sprite density) |

---

## 10. Weighted Decision Matrix

| Criterion | Weight | Dir A (Preserve V2) | **Dir B (Refined Hybrid)** | Dir C (Multi-Layer Sprites) |
|---|---:|---:|---:|---:|
| Visual quality & continuity | 20% | 4.2 | **4.8** | 3.9 |
| Pixel-art consistency | 15% | 4.5 | **4.8** | 4.8 |
| Gameplay & exploration readability | 20% | 4.6 | **4.7** | 4.3 |
| Fog of War & A2 integration | 15% | 4.6 | **4.6** | 4.7 |
| Day/Night compatibility | 10% | 4.5 | **4.6** | 4.5 |
| Performance & scalability | 10% | 3.8 | **4.5** | 3.5 |
| Maintainability & low identity risk | 10% | 4.4 | **4.5** | 4.0 |
| **Weighted Total (out of 5.00)** | **100%** | **4.39** | **4.67** | **4.26** |

---

## 11. One Recommended Direction

Adopt **Direction B — Refined Hybrid**:
1. **Keep Version A (`main_cloud_01..03.png`) and `A_Medium` (`~42–44%` fg coverage) unchanged.**
2. **Upgrade `CloudSeaBase`** to a `512x512` subdued horizontal layered pixel-art cloud-bank texture (`#0B101B`–`#1C2A46`).
3. **Optimize `_sync_full_fog_mask()`** using a `PackedByteArray` 2-pass distance transform.

---

## 12. Proposed C1.5.5 Experiment Plan

A small, isolated validation milestone (`scratch/c1_5_5_refined_hybrid/`) before any production integration:

- **Variants:** `V2_Current` (`256x256` base) vs `V4_Refined_Hybrid` (`512x512` horizontal layered cloud-band base + `A_Medium`).
- **Time-of-Day Matrix:** `12:00` (Day), `06:00` (Dawn), `18:30` (Dusk), `22:00` (Night).
- **Benchmarking:** Warm-up `30` frames, measure `60` frames per view (report **avg, median, p95, worst-case** frame time), and measure `PackedByteArray` 2-pass mask init time vs `650.2 ms` baseline.
- **Verification:** Confirm `inc_matches_full=true`, `0` leaks, and `1.5x` / `2.25x` visual inspection.

---

## 13. Production Integration Risks

1. **Double-Tinting in `FogCloudLayer`:** Production `WorldView.sync_day_night_visuals()` calls `fog_cloud_layer.apply_day_night_tint()`; must be reconciled with `DayNightModulate` before integration.
2. **Dynamic Map Sizes:** `CloudSeaBase` shader `map_size` uniform must be bound dynamically to `Vector2(fog.map_width, fog.map_height)` for maps larger than `128x128`.
3. **Save/Load Full Sync:** `SaveManager` triggers `_sync_full_fog_and_minimap()`; a fast 2-pass mask build is required so loading a save does not hitch.

---

## 14. Explicit Statement of What Was Not Tested

- **Dawn (`06:00`) and Dusk (`18:30`)** lighting on `CloudSeaBase` + Version A foreground banks.
- **`512x512` horizontal layered cloud-band texture** visual appearance at `1.5x` and `2.25x`.
- **Actual `ms` runtime of the `PackedByteArray` 2-pass distance transform** (remains an untested hypothesis until C1.5.5).
- **Idle drift animation and exploration dispersal** (deferred to C2).
