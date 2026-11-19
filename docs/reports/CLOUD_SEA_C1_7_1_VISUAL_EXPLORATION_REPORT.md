# CLOUD SEA C1.7.1 — VISUAL EXPLORATION REPORT
## Volumetric Atmospheric Fog Sea: Isolated Prototypes A, B & C

**Project:** KINGDOMS UNBOUND  
**Engine:** Godot 4.7-stable (`Forward+`, `TEXTURE_FILTER_LINEAR` for volumetric fog vs. `TEXTURE_FILTER_NEAREST` for pixel-art world)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Production Baseline:** C1.6.3 + C1.6.3-R1 (completely untouched)  
**Milestone:** C1.7.1 — Isolated Visual Research & Prototype Exploration  

---

## 1. Artistic Interpretation of Reference Image 2

Reference Image 2 establishes a deliberate visual contrast between a crisp, readable fantasy settlement and a **continuous, non-pixelated, painterly sea of volumetric fog and smoke** that surrounds it:
- **Continuous Environment vs. Placed Objects:** Fog is not a collection of discrete cloud sprites or horizontal bands; it is an enveloping atmospheric volume with large interconnected masses, deep shadowed troughs, and soft desaturated highlights.
- **Organic, Asymmetric Boundary:** The revealed settlement does not sit inside a rectangular/diamond cutout or a simple Gaussian-blurred mask. Instead, billowing fog lobes and thin wispy tendrils roll irregularly over the outer terrain edge, leaving natural gaps where trees, rocks, and ground peek through while keeping the central settlement unobstructed.
- **Kingdoms Unbound Palette Adaptation:** Rather than bright white fog, the prototypes translate the volumetric form and tonal modeling of Reference Image 2 into Kingdoms Unbound's deep navy (`#080E1C`), blue-black, slate-blue (`#1E2E4A`), muted blue-gray (`#384A69`), and soft desaturated cool highlights (`#7E92B0`).

---

## 2. How the New Fog Differs from the Previous Pixel-Cloud System

| Dimension | Previous System (C1.6.3 / Version A) | New Direction (C1.7.1 Volumetric Fog Sea) |
|---|---|---|
| **Visual Language** | Nearest-neighbor pixel-art sprites (`main_cloud_01..03.png`) + tiled `CloudSeaBase` | Smooth, non-pixelated, painterly volumetric smoke (`TEXTURE_FILTER_LINEAR`) |
| **Structure** | ~440 individual `Sprite2D` nodes placed on a Poisson lattice | 2–3 world-space `Polygon2D` shader passes with multi-scale domain-warped FBM |
| **Continuity** | Overlapping discrete cloud objects | Continuous, interconnected fog masses with internal 3D normal-based light/shadow |
| **Boundary** | Pixel-cloud silhouettes + `4`-tile Manhattan fog mask | Dual-channel Chamfer SDF (`fog_mask`) + multi-scale world-space domain-warped lobes & wisps |
| **Camera Stability** | Fixed world sprites | 100% world-space shader coordinates (`MODEL_MATRIX * VERTEX`), zero texture swimming on pan/zoom |

---

## 3. Prototype A — Dense Connected Fog Banks

- **Artistic Goal:** High continuity, thick billowing fog banks with small negative-space troughs and broad, heavy rolling boundary lobes.
- **Technical Approach:** `2` `Polygon2D` shader passes:
  1. `deep_foundation.gdshader` (`z = 6`): Deep navy/blue-black organic foundation.
  2. `proto_a_dense_banks.gdshader` (`z = 7`): Domain-warped 3-octave world-space FBM heightfield (`fog_noise_a` + `fog_noise_b` at non-harmonic rotated scales) with finite-difference normal lighting (`eps = 30.0 px`) and high density continuity (`smoothstep(0.22, 0.72, ...)`).

---

## 4. Prototype B — Layered Atmospheric Smoke

- **Artistic Goal:** Strongest depth separation, more negative space revealing the dark foundation between smoke banks, and fluid wispy tendrils bridging formations and drifting across the frontier.
- **Technical Approach:** `3` `Polygon2D` shader passes:
  1. `deep_foundation.gdshader` (`z = 6`): Deep navy/blue-black atmospheric base.
  2. `proto_b_mid_smoke.gdshader` (`z = 7`): Primary billowing smoke masses with wider negative-space troughs (`smoothstep(0.32, 0.78, ...)`) and soft volumetric shading (`eps = 28.0 px`).
  3. `proto_b_wisps.gdshader` (`z = 8`): Dedicated semi-transparent upper wisp layer (`alpha <= 0.52`) using flow-warped anisotropic noise (`rot2(...) * vec2(0.65, 1.45)`) extending slightly further over the frontier boundary.

---

## 5. Prototype C — Rolling Volumetric Mist

- **Artistic Goal:** More dramatic, swirling, asymmetric silhouettes and internal eddies without becoming visually noisy.
- **Technical Approach:** `2` `Polygon2D` shader passes:
  1. `deep_foundation.gdshader` (`z = 6`): Deep navy/blue-black base.
  2. `proto_c_rolling_mist.gdshader` (`z = 7`): 2-stage curl/domain-warped FBM + soft billow shaping (`smoothstep(0.18, 0.85, billow_src)`), broad normal shading (`eps = 28.0 px`), and stronger swirl-warped boundary tongues.

---

## 6. Technical Architecture Summary (Shared Foundation)

- **Noise Assets:** Two `512×512` seamless `RGBA8` multi-channel textures (`fog_noise_a.png`, `fog_noise_b.png`) generated via `FastNoiseLite` (`TYPE_SIMPLEX_SMOOTH`, `FRACTAL_FBM`, `seamless = true`) and sampled with `filter_linear_mipmap, repeat_enable` at irrational rotated scales (`0.23`, `1.07`, `2.09` rad) to eliminate any visible tiling.
- **Authoritative `FogOfWar` Organic Boundary:** `_build_dual_sdf_mask(fow)` computes a 2-pass Chamfer `(1.0, 1.414)` distance field (`128×128`, `FORMAT_RGBA8`, `TEXTURE_FILTER_LINEAR`) storing `R = dist_into_unexplored / 10.0` and `G = dist_into_explored / 6.0`. Shaders domain-warp `(u, v)` before sampling `R` for irregular lobes/wisps, while `G` (`safe_inner`) guarantees zero fog over the inner settlement core.
- **World-Space Stability:** `v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy` keeps all noise and boundary warps locked to world pixels across `0.75×`, `1.5×`, and `2.2×` zoom levels.

---

## 7. Screenshots at Identical Camera Conditions

All captures taken on `WorldView` (`128×128`, `seed = 12345`, `12:00` Day, `1280×720`):
- **Side-by-Side Comparison (Settlement `1.5×`, Deep Sea `1.5×`, Boundary `2.2×`, Wide `0.75×`):**  
  `scratch/c1_7_1_atmospheric_fog/screenshots/comparison_a_b_c.png`
- **Individual Prototypes:**
  - Prototype A: `proto_a_settlement.png`, `proto_a_deep_sea.png`, `proto_a_boundary.png`, `proto_a_wide.png`
  - Prototype B: `proto_b_settlement.png`, `proto_b_deep_sea.png`, `proto_b_boundary.png`, `proto_b_wide.png`
  - Prototype C: `proto_c_settlement.png`, `proto_c_deep_sea.png`, `proto_c_boundary.png`, `proto_c_wide.png`

---

## 8. Close-Up Boundary Comparisons (`2.2×` Zoom)

- **Prototype A (`proto_a_boundary.png`):** Broad, dense billowing lobes softly overlap the grass/dirt frontier; very cohesive, slightly heavier edge.
- **Prototype B (`proto_b_boundary.png`):** Best multi-tiered edge transition—dense mid-layer smoke lobes backed by translucent, curved wispy tendrils drifting softly over the outer trees and shoreline while keeping all settlement buildings and citizens crisp.
- **Prototype C (`proto_c_boundary.png`):** Dynamic swirling mist tongues with stronger internal eddies and slightly busier edge texture.

---

## 9. Performance Observations

Measured in `run_prototypes.gd` (`1280×720`, NVIDIA RTX 3050 Ti Laptop GPU, Forward+):

| Metric | Prototype A (2 passes) | Prototype B (3 passes) | Prototype C (2 passes) |
|---|---:|---:|---:|
| **SDF Mask Build (`128×128`, CPU)** | `27.307 ms` (one-time / incremental) | `27.307 ms` | `27.307 ms` |
| **Frame Time — Settlement (`1.5×`)** | `5.558 ms` | `4.751 ms` | `5.247 ms` |
| **Frame Time — Deep Sea (`1.5×`)** | `6.996 ms` | `6.417 ms` | `7.075 ms` |
| **Frame Time — Boundary (`2.2×`)** | `6.351 ms` | `7.131 ms` | `5.346 ms` |
| **Frame Time — Wide (`0.75×`)** | `7.166 ms` | `8.725 ms` | `6.950 ms` |
| **Sprite2D Count** | `0` | `0` | `0` |

- **Transparent Overdraw:** 2–3 full-viewport `Polygon2D` passes (`~2×–3×` overdraw) replace 440+ overlapping `Sprite2D` nodes, maintaining `~4.7–8.7 ms` frame times (~115–210 FPS) across all zoom levels.

---

## 10. Strengths and Weaknesses of Each Prototype

| Prototype | Strengths | Weaknesses |
|---|---|---|
| **A — Dense Connected Fog Banks** | Lowest overdraw (2 passes); very cohesive, calm cloud-sea silhouette; minimal visual noise. | Less depth separation and fewer translucent wisps bridging formations. |
| **B — Layered Atmospheric Smoke** | **Best visual depth, negative-space balance, and wispy organic boundary**; clearly reads as layered volumetric smoke around a pixel-art settlement. | 3 transparent passes (`~8.7 ms` at `0.75×` wide zoom vs `~7.0 ms` for 2 passes). |
| **C — Rolling Volumetric Mist** | Strongest internal swirl/eddy energy and 2-pass overdraw budget. | Finer swirl filaments look slightly busier/turbulent than the calm painterly smoke of Reference Image 2. |

---

## 11. Recommended Direction

**Recommend: Prototype B — Layered Atmospheric Smoke** (with optional subtle billow-crest softening from Prototype A).

**Evidence:**
1. Visual inspection of `proto_b_settlement.png` and `proto_b_boundary.png` shows the clearest realization of all 4 conceptual layers: deep navy foundation visible in troughs, soft billowing mid-layer smoke banks, and fluid translucent wisps that make the frontier look naturally enveloped rather than cut out.
2. Zero pixelation, zero sprite lattice, zero repeating tiles, and 100% world-space stability across `0.75×`, `1.5×`, and `2.2×` zoom.
3. Practical production performance (`4.75–8.73 ms` frame time, `0` cloud `Sprite2D` nodes, and a clean path to incremental dirty-rect SDF updates in C1.7.2).

---

## 12. Exact List of Files Created and Modified

**Created (isolated under `scratch/c1_7_1_atmospheric_fog/` and `docs/reports/`):**
- `scratch/c1_7_1_atmospheric_fog/generate_noise_textures.gd`
- `scratch/c1_7_1_atmospheric_fog/run_prototypes.gd`
- `scratch/c1_7_1_atmospheric_fog/assets/fog_noise_a.png`
- `scratch/c1_7_1_atmospheric_fog/assets/fog_noise_b.png`
- `scratch/c1_7_1_atmospheric_fog/shaders/deep_foundation.gdshader`
- `scratch/c1_7_1_atmospheric_fog/shaders/proto_a_dense_banks.gdshader`
- `scratch/c1_7_1_atmospheric_fog/shaders/proto_b_mid_smoke.gdshader`
- `scratch/c1_7_1_atmospheric_fog/shaders/proto_b_wisps.gdshader`
- `scratch/c1_7_1_atmospheric_fog/shaders/proto_c_rolling_mist.gdshader`
- `scratch/c1_7_1_atmospheric_fog/screenshots/comparison_a_b_c.png`
- `scratch/c1_7_1_atmospheric_fog/screenshots/proto_{a,b,c}_{settlement,deep_sea,boundary,wide}.png` (12 PNGs)
- `docs/reports/CLOUD_SEA_C1_7_1_VISUAL_EXPLORATION_REPORT.md`

**Modified:** None.

---

## 13. Production Preservation Confirmation

Confirmed via `git diff` / `git status`: zero production scripts (`fog_cloud_layer.gd`, `world_view.gd`, `save_manager.gd`, `FogOfWar`, Fast Fog Mask), zero production scenes, and zero existing cloud assets were modified, overwritten, or deleted. Nothing was staged, committed, or pushed, and C1.7.2 / C1.6.4 was not started.
