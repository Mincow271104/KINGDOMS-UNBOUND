# C1.9.2 M2-C2B-R1 Owner Follow-up — Preview Center Alignment & Envelope Coverage Investigation

**Date:** 2026-11-16  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** Read-only investigation & isolated visual experimentation (`0` production files modified)  
**Engine:** Godot `v4.7.stable.official.5b4e0cb0f` (`D3D12 12_0 - Forward+`)

---

## 1. Exact Runtime Coordinates (`world_view.tscn`, Seed `12345`, Zoom `1.0x`)

| Entity / Reference | Grid Coord | World-Space Coord (`px`) | Screen Coord at `1.0x` (`px`) |
|---|---|---|---|
| `world_data.center_spawn` | `(64, 65)` | `(-16.0, 1032.0)` | `(640.0, 360.0)` |
| Actual Town Hall (`buildings_by_cell["townhall"]`) | `(63, 62)` | `(16.0, 1000.0)` | `(672.0, 328.0)` |
| Town Hall `Node2D.position` (`2×2` footprint anchor) | — | `(16.0, 1032.0)` | `(672.0, 360.0)` |
| `Camera2D.position` / `screen_center` | — | `(-16.0, 1032.0)` | `(640.0, 360.0)` |
| M2-C2B-R1 synthetic `HUNTER_SCOUT` source | `(50, 69)` (`spawn + (-14, 4)`) | `(-304.0, 952.0)` | `(352.0, 280.0)` |
| M2-C2B-R1 synthetic `SOLDIER` source | `(64, 80)` (`spawn + (0, 15)`) | `(-256.0, 1152.0)` | `(400.0, 480.0)` |

- **Town Hall vs `center_spawn` offset:** `(-1, -3)` grid cells = `(+32.0, -32.0) px` in world/screen space.
- **Town Hall vs M2-C2B-R1 synthetic preview sources:** The M2-C2B-R1 capture script intentionally placed synthetic `HUNTER_SCOUT` and `SOLDIER` sources off to the southwest/left of the settlement (`(-304, 952)` and `(-256, 1152)`) without any `TOWN_HALL` source at `(63, 62)`.

---

## 2. Coordinate Transformation Chain Audit

Verified end-to-end across `IsoMath`, `TerrainPreviewField`, `terrain_preview_envelope.gdshader`, and `cloud_sea_composite.gdshader`:

1. **`IsoMath.grid_to_world(g)` (`scripts/utils/iso_math.gd`):**
   `lx = (g.x - g.y) * 16.0`, `ly = (g.x + g.y) * 8.0`.
2. **`TerrainPreviewField` (`scripts/world/terrain_preview_field.gd`):**
   Stores `center_iso = IsoMath.grid_to_world(cell)` directly into `source_data_tex` (`RG` of row `0`).
3. **`terrain_preview_envelope.gdshader` (`shaders/fog/terrain_preview_envelope.gdshader`):**
   `uv_grid = UV * map_size - 0.5;`
   `p_iso = vec2((uv_grid.x - uv_grid.y) * 16.0, (uv_grid.x + uv_grid.y) * 8.0);`
   At texel `(i, j)` center (`UV = (i + 0.5) / 128.0`), `uv_grid = (i, j)` -> `p_iso == IsoMath.grid_to_world(Vector2i(i, j))` (`0.000 px` error).
4. **`cloud_sea_composite.gdshader` (`shaders/fog/cloud_sea_composite.gdshader`):**
   `u_grid = (v_world_pos.x / 32.0) + (v_world_pos.y / 16.0);`
   `v_grid = (v_world_pos.y / 16.0) - (v_world_pos.x / 32.0);`
   `mask_uv = (vec2(u_grid, v_grid) + 0.5) / map_size;`
   At `v_world_pos = IsoMath.grid_to_world(Vector2i(i, j))`, `mask_uv = (i + 0.5, j + 0.5) / 128.0`, hitting the exact texel center of `envelope_tex`, `fog_state_tex`, and `transition_tex`.

**Audit Finding:** **Zero** half-cell, origin, offset, axis, or scaling discrepancies exist in the coordinate pipeline.

---

## 3. Current Center Offsets & Boundary Decomposition

In the M2-C2B-R1 baseline (`A_baseline_100x.png`), with `FogOfWar` having `VISIBLE` radius `8` around `spawn (64, 65)` + `EXPLORED_NOT_VISIBLE` from `reveal_circle(spawn + (10, 0), 6)`:
- **Isolated `FogOfWar`-only opening (no preview sources):** `left=445, right=918, top=222, bottom=508` (`474×287 px`, `rx=237.0, ry=143.5`, center `(681.5, 365.0)`).
  - **Cause:** `FogOfWar.update_observers()` / `reveal_circle()` uses Manhattan distance (`|dx| + |dy| <= r`), which projects to an axis-aligned **horizontal/vertical rectangle** in 2:1 isometric screen space, softened at the edge by `FogTransitionViewport` (`256×256` Gaussian coverage).
- **Combined Baseline A (`HUNTER_SCOUT` + `SOLDIER` off-center left):** `left=54, right=918, top=52, bottom=664` (`865×613 px`, center `(486.0, 358.0)`).
  - Town Hall screen `(672, 328)` is offset **`(+186.0, -30.0) px`** from the visible opening center!
  - Left/top/bottom boundaries come from `TerrainPreviewField` + `CloudSeaComposite`, while the **right boundary (`x=918`)** comes directly from `FogOfWar` (`VISIBLE`/`EXPLORED_NOT_VISIBLE`) colliding with the opaque cloud sea because there was no preview source covering the kingdom's east side.

---

## 4. Controlled Variants Comparison (A / B / C / D / E, Seed `12345`, Zoom `1.0x`)

All variants keep `FogOfWar` data 100% identical (`reveal_circle(spawn+(10,0), 6)` + `update_observers(spawn, r=8)`).

| Variant | Preview Source Center(s) | Radii (`preview / core px`) | Opening BBox (`px`) | Opening Size (`rx / ry`) | Town Hall Offset from Opening Center (`px`) | Outer Cloud Edge | Inner `EXPLORED_NOT_VISIBLE` Rectangle Still Visible? |
|---|---|---|---|---|---|---|---|
| **A (Baseline)** | `spawn+(-14,4)`, `spawn+(0,15)` | `185/0`, `165/95` | `[54..918, 52..664]` | `865×613` (`432.5 / 306.5`) | `(+186.0, -30.0)` | Clipped on right by `FogOfWar` | **Yes** (half-clipped on right by cloud sea) |
| **B (Same pos, larger)** | `spawn+(-14,4)`, `spawn+(0,15)` | `380/220`, `340/200` | `[10..918, 52..664]` | `909×613` (`454.5 / 306.5`) | `(+208.0, -30.0)` | Still off-center left; east side still hits `FogOfWar` | **Yes** |
| **C (Centered, default r)** | `town_hall (63,62)` | `310 / 165` | `[230..1079, 52..664]` | `850×613` (`425.0 / 306.5`) | `(+17.5, -30.0)` | **Centered & organic** around kingdom | **Yes** — dark `474×287` mist box remains inside opening |
| **D (Centered, larger r)** | `town_hall (63,62)` | `440 / 280` | `[77..1079, 52..664]` | `1003×613` (`501.5 / 306.5`) | `(+94.0, -30.0)`* | **Centered, wide**, shows surrounding coastline | **Yes** — dark `474×287` mist box remains inside opening |
| **E (Centered + asymmetric)** | `town_hall (63,62)` + `(-8,5)` + `(6,-3)` | `410/260`, `250/140`, `210/120` | `[44..1079, 52..664]` | `1036×613` (`518.0 / 306.5`) | `(+110.5, -30.0)`* | **Centered, organic, asymmetric** (matches target silhouette) | **Yes** — dark `474×287` mist box remains inside opening |

*\*Note: In D and E, the measured opening reaches the HUD minimap exclusion bound (`x=1079`) on the right and HUD bars (`y=52, 664`) on top/bottom at `1.0x` zoom; `0.75x` captures confirm the full unclipped envelope is centered on the Town Hall.*

---

## 5. Visual Captures

All captures are stored in conversation scratch `m2_c2b_r1_center_audit/`:
- `A_baseline_100x.png`, `B_same_pos_larger_100x.png`, `C_centered_default_r310_100x.png`, `D_centered_larger_r440_100x.png`, `E_centered_asymmetric_100x.png`
- `0.75x` and `1.5x` zoom captures for **D** and **E**: `D_centered_larger_{75,150}x.png`, `E_centered_asymmetric_{75,150}x.png`.

Visual inspection confirms:
- Moving the preview center to `town_hall (63, 62)` (**C**, **D**, **E**) immediately eliminates the off-center coastline cutout and frames the kingdom inside a natural, volumetric cloud-sea opening (`D` / `E` at `0.75x` and `1.0x` match the target composition's outer cloud-sea silhouette).
- **However**, even in **D** (`r=440`) and **E** (asymmetric), the **inner dark rounded-rectangular box** around the settlement (`VISIBLE <-> EXPLORED_NOT_VISIBLE`) remains clearly visible inside the cloud opening!

---

## 6. Entity Visibility Invariants

- No production code, `FogOfWar` state, or entity visibility logic was modified.
- All variants only changed isolated `TerrainPreviewField` fixture sources; hidden resources, POIs, wildlife, monsters, and enemy military remain strictly gated by `FogOfWar`.

---

## 7. Conclusion & Recommended Next Step

**Conclusion: Hypothesis PARTIALLY CONFIRMED**
1. **Confirmed for the outer cloud-sea opening:** The off-center coastline cutout in M2-C2B-R1 was indeed caused by uncentered synthetic preview sources (`(-14, 4)` / `(0, 15)` without a `TOWN_HALL` source). Centering a `TOWN_HALL` source at `(63, 62)` with `r = 310–440 px` (especially **E**'s slightly asymmetric profile) places the kingdom naturally in the center of an organic cloud opening showing surrounding terrain and coastline.
2. **Rejected for the inner dark rectangular frame:** Enlarging and centering the preview envelope does **not** hide the inner dark rounded-rectangular silhouette when `EXPLORED_NOT_VISIBLE` terrain surrounds `VISIBLE` terrain. That dark rectangle is produced by `FogOfWar`'s Manhattan distance (`|dx| + |dy| <= r`, which is an axis-aligned rectangle in 2:1 isometric projection) rendered with `mist_alpha = 0.46` (`vec4(0.06, 0.09, 0.14, 0.46)`).

**Recommended Next Step (for Owner Approval):**
1. **In M2-C3**, wire the real `TOWN_HALL` preview source at `town_hall_grid` (`r ~ 380–420 px` or paired with subtle organic lobe) so the outer cloud opening is always centered on the kingdom.
2. **For the inner `EXPLORED_NOT_VISIBLE` mist box** (without rewriting `FogOfWar` Manhattan gameplay visibility): soften the visual-only `EXPLORED_NOT_VISIBLE` presentation in `cloud_sea_composite.gdshader` / `fog_transition_coverage.gdshader` (e.g., lower `mist_alpha` from `0.46` to `~0.26–0.30` and increase cloud-bank modulation `(bank - 0.48) * 0.65` + wider transition feather on `vis_cov`) so `EXPLORED_NOT_VISIBLE` reads as subtle atmospheric haze rather than a dark rectangular stencil.
