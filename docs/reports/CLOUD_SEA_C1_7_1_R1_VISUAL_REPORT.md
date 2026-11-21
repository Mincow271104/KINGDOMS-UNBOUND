# CLOUD SEA C1.7.1-R1 — VISUAL REPORT
## Art Direction Correction: Soft Cloud Banks & Atmospheric Mist

**Project:** KINGDOMS UNBOUND  
**Engine:** Godot 4.7-stable (`Forward+`, `TEXTURE_FILTER_LINEAR` for fog vs. `TEXTURE_FILTER_NEAREST` for pixel-art world)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Production Baseline:** C1.6.3 + C1.6.3-R1 (completely untouched)  
**Milestone:** C1.7.1-R1 — Isolated Visual Redesign & Prototype Iteration  

---

## 1. Artistic Interpretation of Reference Image 2 & What Changed

Following the owner's rejection of C1.7.1's marble-like swirls, dark palette, and ring-like boundary, the visual shape language was completely redesigned around Reference Image 2:

1. **Cloud Shape Language (Soft Cloud Banks, Not Swirled Liquid):**
   - Replaced domain-warped FBM / curl noise / finite-difference micro-normals with **broad, overlapping cumulus-like cloud lobes** (`soft_cloud_banks.png`, `512×512` seamless RGBA8 generated from clustered soft radial puffs + ultra-low-frequency smooth variation).
   - Zero marble veins, zero contour lines, zero turbulent streaks.
2. **Brighter, Calm, Spacious Palette:**
   - Replaced the near-black/oppressive `#080E1C` base with a calm, luminous slate-blue and cool blue-gray palette:
     - Deep mist / open valleys: `#2A3955` – `#3E506F` (`vec3(0.165, 0.225, 0.335)` to `vec3(0.245, 0.315, 0.435)`)
     - Cloud bank shadow / underside: `#465A78` (`vec3(0.275, 0.345, 0.465)`)
     - Cloud bank body: `#798DA9` (`vec3(0.475, 0.555, 0.665)`)
     - Broad gentle cloud crests: `#ACBED4` (`vec3(0.675, 0.745, 0.830)`) — soft and diffuse, never harsh white.
3. **Broad, Gentle Lighting:**
   - Replaced `16–30 px` finite-difference normal lighting with a **broad `85–95 px` directional shadow offset**, producing creamy, gentle top-left highlights and soft shadowed undersides.
4. **No Continuous Fog Ring Around the Settlement:**
   - Added macro-scale asymmetric sector modulation (`~0.00022` world frequency) to the `FogOfWar` Chamfer SDF boundary so some perimeter edges remain open and breathable (e.g., upper-right shoreline) while broad, soft cloud lobes extend gently over other outer edges without touching the central settlement.

---

## 2. Revised Variants (A, B, C)

- **Variant A — Broad Soft Cloud Banks** (`2` passes: `mist_foundation.gdshader` + `variant_a_broad_banks.gdshader`): Largest, puffiest interconnected cloud formations, very smooth low-contrast internal shading, calm and spacious.
- **Variant B — Layered Cloud Banks and Mist** (`3` passes: `mist_foundation.gdshader` + `variant_b_banks.gdshader` + `variant_b_mist.gdshader`): Clearer separation and open slate-blue valleys between primary cloud banks, bridged by a soft, diffuse secondary translucent mist layer (`alpha <= 0.36`, zero swirls).
- **Variant C — Diffuse Atmospheric Cloud Sea** (`2` passes: `mist_foundation.gdshader` + `variant_c_diffuse_sea.gdshader`): Softest, most diffuse density gradients and widest open spaces for a calm, airy atmosphere.

---

## 3. Technical Implementation & Palette Decisions

- **Seamless Cloud-Bank Texture (`generate_cloud_bank_textures.gd`):** Builds `soft_cloud_banks.png` (`512×512`, `FORMAT_RGBA8`) with `R` = macro puff clusters (`22` clusters × `3–5` lobes, radius `58–125 px`), `G` = secondary puff clusters (`34` clusters, radius `40–92 px`), and `B/A` = ultra-low-frequency smooth `FastNoiseLite` (`freq = 0.0032–0.0045`, `2` octaves).
- **World-Space Stability:** All shaders evaluate `v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy` with `TEXTURE_FILTER_LINEAR`, guaranteeing zero texture swimming when panning or zooming (`0.75×`, `1.5×`, `2.2×`).
- **Authoritative `FogOfWar` SDF (`_build_dual_sdf_mask`):** 2-pass Chamfer `(1.0, 1.414)` distance transform (`128×128`, `FORMAT_RGBA8`, `TEXTURE_FILTER_LINEAR`) encoding `R = dist_into_unexplored / 12.0` and `G = dist_into_explored / 6.0`. Unexplored territory reaches `alpha = 1.0` cleanly with zero terrain bleed-through.

---

## 4. Screenshots & Comparison (`1280×720`, `128×128`, `seed = 12345`, `12:00` Day)

All screenshots saved under `scratch/c1_7_1_r1_cloud_banks/screenshots/`:
- **Side-by-Side Comparison (Deep Sea `1.5×`, Settlement `1.5×`, Boundary `2.2×`, Wide `0.75×`):** `comparison_a_b_c.png`
- **Fog-Disabled Baseline:** `no_fog_settlement.png` (confirms underlying settlement, terrain, trees, houses, and citizens remain 100% unchanged).
- **Individual Views:** `variant_{a,b,c}_{deep_sea,settlement,boundary,wide}.png` (12 PNGs).

---

## 5. Performance Measurements

Measured in `run_r1_prototypes.gd` (`1280×720`, NVIDIA RTX 3050 Ti Laptop GPU, Forward+):

| Metric | Variant A (2 passes) | Variant B (3 passes) | Variant C (2 passes) |
|---|---:|---:|---:|
| **Dual SDF Build (`128×128`, CPU)** | `30.469 ms` | `30.469 ms` | `30.469 ms` |
| **Deep Sea (`1.5×`)** | `4.911 ms` | `5.625 ms` | `4.743 ms` |
| **Settlement (`1.5×`)** | `6.114 ms` | `5.268 ms` | `5.532 ms` |
| **Boundary Close-Up (`2.2×`)** | `4.307 ms` | `5.156 ms` | `4.696 ms` |
| **Wide View (`0.75×`)** | `6.868 ms` | `5.874 ms` | `5.589 ms` |
| **Cloud `Sprite2D` Nodes** | `0` | `0` | `0` |

---

## 6. Remaining Shortcomings & Observations

- At `0.75×` wide zoom, individual macro puff lobes are slightly soft/pillow-blurred (`smoothstep` on `512×512`); in a future production pass (C1.7.2), adding a subtle `1024×1024` secondary lobe variation or tuning lobe cluster sharpness can crisp up macro silhouettes further if desired.
- Variant B offers the richest atmospheric depth and clearest separation between cloud banks and open mist valleys, while Variant A is the simplest 2-pass baseline and Variant C is the most diffuse/open.

---

## 7. Exact List of Files Created and Modified

**Created (isolated under `scratch/c1_7_1_r1_cloud_banks/` and `docs/reports/`):**
- `scratch/c1_7_1_r1_cloud_banks/generate_cloud_bank_textures.gd`
- `scratch/c1_7_1_r1_cloud_banks/run_r1_prototypes.gd`
- `scratch/c1_7_1_r1_cloud_banks/assets/soft_cloud_banks.png`
- `scratch/c1_7_1_r1_cloud_banks/shaders/mist_foundation.gdshader`
- `scratch/c1_7_1_r1_cloud_banks/shaders/variant_a_broad_banks.gdshader`
- `scratch/c1_7_1_r1_cloud_banks/shaders/variant_b_banks.gdshader`
- `scratch/c1_7_1_r1_cloud_banks/shaders/variant_b_mist.gdshader`
- `scratch/c1_7_1_r1_cloud_banks/shaders/variant_c_diffuse_sea.gdshader`
- `scratch/c1_7_1_r1_cloud_banks/screenshots/no_fog_settlement.png`
- `scratch/c1_7_1_r1_cloud_banks/screenshots/comparison_a_b_c.png`
- `scratch/c1_7_1_r1_cloud_banks/screenshots/variant_{a,b,c}_{deep_sea,settlement,boundary,wide}.png` (12 PNGs)
- `docs/reports/CLOUD_SEA_C1_7_1_R1_VISUAL_REPORT.md`

**Modified:** None.

---

## 8. Confirmation of Production Preservation

Confirmed: `scripts/world/fog_cloud_layer.gd`, `scripts/world/world_view.gd`, `scripts/persistence/save_manager.gd`, `FogOfWar`, the Fast Fog Mask implementation, all existing cloud assets, Day/Night production integration, Save/Load, and C1.7.1's previous `scratch/c1_7_1_atmospheric_fog/` directory remain completely untouched. Nothing was staged, committed, or pushed, and C1.7.2 / C1.6.4 was not started.
