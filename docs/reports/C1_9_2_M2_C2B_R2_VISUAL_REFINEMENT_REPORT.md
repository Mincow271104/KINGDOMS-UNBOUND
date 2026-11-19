# C1.9.2 M2-C2B-R1-R2 — Visual Refinement Investigation Report

**Date:** 2026-11-16  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** Isolated visual investigation (`0` production files modified)  
**Engine:** Godot `v4.7.stable.official.5b4e0cb0f` (`D3D12 12_0 - Forward+`)

---

## 1. Objective & Constraints

Investigate and refine two visual issues identified after the center-alignment audit, without modifying any production code, `FogOfWar` semantics, `SaveManager`, or activating `use_cloud_sea_composite` by default:
1. Reduce the oversized outer cloud opening (`410–440 px` + secondary lobes) to a moderate, balanced frame around the kingdom.
2. Eliminate the dark rounded-rectangular `EXPLORED_NOT_VISIBLE` frame inside the cloud opening.

---

## 2. Outer Cloud Opening Radius Comparison (Unclipped World-Space Measurements)

Measured directly from `envelope_tex` (`preview_sd <= 0.0` mapped via `IsoMath.grid_to_world`) with a single `TOWN_HALL` source at `town_hall_grid = (63, 62)` (`th_world = (16.0, 1000.0) px`):

| Variant | Preview / Core Radius (`px`) | World Envelope Center (`px`) | Town Hall World Offset (`px`) | Unclipped World Dimensions (`W × H px`) | World Radii (`rx / ry px`) | Visual Assessment (`1.0x` Zoom) |
|---|---:|---|---|---|---|---|
| **R_A_310** | `310 / 165` | `(24.0, 992.0)` | `(-8.0, 8.0)` | `720.0 × 608.0` | `360.0 / 304.0` | **Best compact** — clouds cleanly frame all 4 edges inside `1280×720` |
| **R_B_350** | `350 / 200` | `(24.0, 988.0)` | `(-8.0, 12.0)` | `816.0 × 696.0` | `408.0 / 348.0` | **Best balanced** — comfortable margin around settlement, coastline & resources visible, clouds frame left/right |
| **R_C_380** | `380 / 225` | `(32.0, 984.0)` | `(-16.0, 16.0)` | `896.0 × 752.0` | `448.0 / 376.0` | Slightly tall; top/bottom cloud edge meets HUD bars at `1.0x` |
| **R_D_410** | `410 / 250` | `(24.0, 988.0)` | `(-8.0, 12.0)` | `976.0 × 808.0` | `488.0 / 404.0` | Oversized at `1.0x`; reveals too much empty perimeter |

*(Note: The `8–16 px` offset between `env_center_world` and `th_world` comes solely from the intentional C1.9.1 `phase_a / phase_b` organic lobe asymmetry.)*

**Best Two Outer Radii:** **`R_B_350` (`350 / 200 px`)** and **`R_A_310` (`310 / 165 px`)**.

---

## 3. `EXPLORED_NOT_VISIBLE` Visual Treatment Comparison (Isolated Shader Overrides at `r = 350 px`)

Tested against identical `FogOfWar` state (`reveal_circle(spawn + (10, 0), 6)` + `update_observers(spawn, r=8)`):

| Treatment | Mist Opacity & Tint | `vis_factor` Transition | Rectangular Silhouette Perceptible? |
|---|---|---|---|
| **M_A (`opacity26`)** | `0.26`, `vec3(0.06, 0.09, 0.14)` | `smoothstep(0.14, 0.88, vis_cov + (bank - 0.48) * 0.34)` | **Moderately perceptible** — lighter, but straight horizontal/vertical box edges remain |
| **M_B (`opacity20_cloudmod`)** | `0.14 + 0.10 * bank`, `vec3(0.08, 0.12, 0.18)` | `smoothstep(0.14, 0.88, vis_cov + (bank - 0.48) * 0.34)` | **Faint** — much softer, slight straight edge at top/bottom |
| **M_C (`opacity46_widefeather`)** | `0.46`, `vec3(0.06, 0.09, 0.14)` | `smoothstep(-0.05, 1.05, vis_cov + (bank - 0.48) * 0.65)` | **Strongly perceptible** — high `0.46` dark contrast still reads as a dark rectangular frame |
| **M_D (`combined_subtle_wide`)** | `0.16 + 0.08 * bank`, `vec3(0.14, 0.20, 0.28)` | `smoothstep(0.00, 0.98, vis_cov + (bank - 0.48) * 0.62)` | **Effectively eliminated** — reads as natural atmospheric haze over explored terrain |

**Best Two Treatments:** **`M_D` (Combined subtle cloud-modulated opacity + wide organic feather)** and **`M_B` (Subtle cloud-modulated opacity)**.

---

## 4. Combined Best Visual Result & Zoom Consistency

**Combined Best:** **`R_B_350` (`preview_radius = 350 px`, `core_radius = 200 px` at Town Hall `(63, 62)`) + `M_D` (`mist_alpha = 0.16 + 0.08 * bank`, `mist_col = vec3(0.14, 0.20, 0.28)`, `vis_factor = smoothstep(0.00, 0.98, vis_cov + (bank - 0.48) * 0.62)`)**.

Verified in conversation scratch (`m2_c2b_r2_refine/`):
- `R_A_310_100x.png`, `R_B_350_100x.png`, `R_C_380_100x.png`, `R_D_410_100x.png`
- `M_A_opacity26_r350_100x.png`, `M_B_opacity20_cloudmod_r350_100x.png`, `M_C_opacity46_widefeather_r350_100x.png`, `M_D_combined_subtle_wide_r350_100x.png`
- Zoom consistency: `M_D_combined_r350_75x.png` (`0.75x`) and `M_D_combined_r350_150x.png` (`1.5x`) confirm the settlement sits centered inside a moderately sized, organic, layered cloud opening with coastline visible and no dark rectangular frame.

---

## 5. Entity Visibility, Performance & Regression Status

- **Entity Visibility Safety:** No production shader, `FogOfWar` grid, or entity visibility code was modified; the M2-C2B-R1 safety invariants (`test_cloud_sea_visibility_safety.gd`: `11/11` passed) remain intact.
- **Performance Impact of `M_D`:** Zero extra textures, zero extra passes, zero CPU/memory overhead (replaces scalar constants in `cloud_sea_composite.gdshader`).

---

## 6. Recommendation for Owner Approval

**APPROVED FOR NEXT IMPLEMENTATION STEP:**
1. Apply **`M_D`** mist parameters (`mist_col = vec3(0.14, 0.20, 0.28)`, `mist_alpha = (0.16 + 0.08 * bank) * ...`, `vis_factor = smoothstep(0.00, 0.98, vis_cov + (bank - 0.48) * 0.62)`) to `shaders/fog/cloud_sea_composite.gdshader`.
2. In **M2-C3**, wire the `TOWN_HALL` preview source centered at `town_hall_grid` with **`preview_radius_px = 350.0`**, **`core_radius_px = 200.0`** (or keep `310 / 165` if a tighter framing is preferred).
