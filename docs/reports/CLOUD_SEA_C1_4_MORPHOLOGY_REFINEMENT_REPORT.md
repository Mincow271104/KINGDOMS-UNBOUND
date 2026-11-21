# KINGDOMS UNBOUND — C1.4 Cloud Morphology Refinement Report

**Milestone:** C1.4 — Artwork-Only Morphology Refinement  
**Status:** Complete — Isolated Assets & Studies Ready for Owner Review (No Production Integration)

---

## 1. Files Inspected & Preservation Confirmation

- **Inspected:**
  - C1.1 original & refined sprites (`scratch/c1_1_candidates/`, `scratch/c1_1_refined/`).
  - C1.3 prototype (`scratch/run_c1_3_cluster_sea.gd`) & screenshots (`c1_3_day_1200_cam1.png`, `c1_3_closeup_overlap.png`).
  - `project.godot` (`textures/canvas_textures/default_texture_filter=0` Nearest, `1280x720`, `Camera2D.zoom = 1.5`).
- **Preserved Untouched:**
  - All C1.1 original and refined PNGs, C1.2/C1.3 prototype scripts & reports, `assets/fog/*`, `FogOfWar`, `FogCloudLayer`, `WorldView`, `SaveManager`, and `FogTileMapLayer`.
  - No Git staging, commits, pushes, resets, or stashes were performed.

---

## 2. New Assets & Exact Dimensions (`scratch/c1_4_morphology/`)

| Asset | Dimensions | Role & Morphology |
|---|---|---|
| `cloud_a_long_layered_bank.png` | `196x86` | Primary horizontal structure: dominant upper-left mass, broad central-right shelf, tapered wind-swept right wing, irregular shallow hanging billows |
| `cloud_b_broad_cumulus.png` | `160x108` | Tall broad cumulus: one dominant asymmetric upper peak merging into broad shoulders and an integrated, undulating underside |
| `cloud_c_wind_swept_extension.png` | `176x52` | Low horizontal bridge: connected uneven horizontal bands with tapered left/right extensions |

---

## 3. Palette Information

Uses the exact 7-color Dark Fantasy ramp with transparent background and zero anti-aliasing or `1px` noise:
- `#0E1322` (deepest shadow — restrained to small lower-right/underside pockets)
- `#161E33` (deep shadow)
- `#202945` (secondary shadow)
- `#2B3856` (primary body)
- `#3D4E73` (midtone)
- `#566B94` (highlight)
- `#6A82AD` (restrained top-crest highlight)

---

## 4. Silhouette, Scale, Composition & Comparison Deliverables

All visual sheets are stored in the artifact directory:
- **B. Silhouette Comparison Sheet:** `c1_4_silhouette_sheet.png` — Confirms broad, flowing horizontal silhouettes without dozens of small spherical bumps.
- **C. Native 1x & 1.5x Nearest-Neighbor Scale:** `c1_4_scale_1x_1_5x.png` — Confirms crisp pixel clusters and readable volume at actual `1.5x` gameplay zoom.
- **D. Three Composition Studies (Using Only Clouds A, B, C):**
  1. `c1_4_comp_1_continuous_bank.png` — Continuous horizontal cloud bank.
  2. `c1_4_comp_2_balanced_masses.png` — Balanced formation with large and small visual masses.
  3. `c1_4_comp_3_loose_channels.png` — Loosely connected formation with visible dark-sky channels.
- **E. C1.1 Refined vs. C1.4 Morphology Comparison:** `c1_4_vs_c1_1_comparison.png` — Demonstrates the elimination of pebble-like lobe fragmentation in favor of merged, flowing cloud banks.

---

## 5. Evaluation & Known Weaknesses

- **Evaluation Against Section 8:** None of the three forms read as a pile of rocks; adjacent lobes merge seamlessly into broad horizontal tonal bands; undersides are irregular and integrated without thick black strips; and all three compositions combine cleanly without obvious repetition.
- **Known Weaknesses:**
  1. In `cloud_b_broad_cumulus.png`, a small `2x2`–`3x2` darker cluster (`#2B3856`) appears near the center of the upper dome from the internal shelf transition (`sdy > 0.45`).
  2. The three composition studies are isolated over `#0A0D16` background; in-game testing inside `WorldView` is deferred until owner approval (C1.5).

---

## 6. Explicit Non-Integration Confirmation

- No production code, scene files, or `assets/fog/` sprites were modified.
- No daytime palette variants were created.
- No Git commit, stage, or push was performed.
