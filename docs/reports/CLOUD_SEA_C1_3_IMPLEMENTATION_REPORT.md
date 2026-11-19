# KINGDOMS UNBOUND — C1.3: Clustered Organic Cloud Sea Implementation & Visual Acceptance Report

**Milestone:** C1.3 — Visual Prototype Only  
**Engine:** Godot 4.7 (`D3D12 Forward+`)  
**Status:** Complete — Isolated Prototype Ready for Owner Review (No Production Rollout)

---

## 1. Git Baseline and Preservation Confirmation

- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **HEAD Commit:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Preservation Verified:**
  - All pre-existing working-tree modifications and untracked files were preserved unchanged.
  - Production `FogOfWar`, `FogCloudLayer`, `WorldView`, `SaveManager`, `TerritoryManager`, and A2 `FogTileMapLayer` were **not** modified during C1.3.
  - The three approved refined Main Cloud Mass PNGs in `scratch/c1_1_refined/` remained **byte-for-byte unchanged**.

---

## 2. Files Created or Modified

- **Created (Repository Report):**
  - [CLOUD_SEA_C1_3_IMPLEMENTATION_REPORT.md](file:///e:/KINGDOMS%20UNBOUND/kingdoms-unbound/docs/reports/CLOUD_SEA_C1_3_IMPLEMENTATION_REPORT.md)
- **Created (Isolated C1.3 Prototype Script & Captures in Artifact/Scratch):**
  - `scratch/run_c1_3_cluster_sea.gd` (isolated prototype runner using `res://scenes/world/world_view.tscn` at `1280x720`, `Camera2D.zoom = 1.5`, seed `12345`)
  - Screenshots saved in artifact directory (`c1_3_day_1200_cam1.png`, `c1_3_dawn_0600_cam1.png`, `c1_3_dusk_1830_cam1.png`, `c1_3_night_2200_cam1.png`, `c1_3_day_1200_cam2_deep_sea.png`, `c1_3_frontier_view.png`, `c1_3_closeup_overlap.png`).
- **Production Files Modified in C1.3:** **None.**

---

## 3. Composition Algorithm Explanation

Replaced C1.2's staggered horizontal lattice (`step_x`, `step_y` rows) with a deterministic **3-Level Hierarchical Organic Cluster Composer**:

1. **Level A — Major Cloud Banks (`76` clusters):**
   - Seeded dart-throwing generates cluster centers across the `128x128` isometric diamond with variable minimum separation (`145.0–240.0 px`), preventing rows, columns, or uniform spacing.
   - Each cluster receives a random influence radius (`115.0–195.0 px`), a wind-swept drift axis (`-0.42..+0.42 rad`), and a target member count (`4–7`), placing a primary anchor (`scale 1.00–1.15`) near the center.
2. **Level B — Supporting Overlapping Masses (`312` instances):**
   - Samples `3–6` supporting formations per cluster using elliptical polar offsets (`1.15x` horizontal, `0.56x` vertical rotated along the cluster's wind axis) with varied minimum center separation (`48.0–74.0 px`).
   - Enforces silhouette diversity (`_pick_diverse_kind` avoids repeating the same sprite within `125 px`) and neighbor scale differentiation (`_pick_varied_scale` ensures `|Δscale| >= 0.07` within `115 px`).
3. **Level C — Independent Bridge Formations (`49` instances):**
   - Dart-throws smaller bridge formations (`scale 0.85–0.96`, `min_dist = 76.0 px`) between clusters to softly connect banks while preserving atmospheric dark-sky channels.
4. **UNEXPLORED Footprint Guard & Y-Sorting:**
   - `_is_footprint_unexplored()` samples a 9-point scaled bounding footprint in `IsoMath.local_to_map()`, rejecting any formation touching `VISIBLE` or `EXPLORED` cells.
   - `y_sort_enabled = true` renders back formations behind front formations so sunlit upper-left domes overlap shadowed lower bases cleanly.

---

## 4. Exact Placement Parameters (`128x128` World, Seed `12345`)

| Parameter | Value |
|---|---|
| `target_clusters` / Actual Placed | `86` / `76` |
| Cluster `min_sep` | `145.0–240.0 px` |
| Cluster `influence_r` | `115.0–195.0 px` |
| Cluster `wind_angle` | `-0.42..+0.42 rad` |
| Cluster `members` target | `4–7` |
| Level B `min_overlap_dist` | `48.0–74.0 px` |
| Level C `target_bridges` / Placed | `70` / `49` (`min_dist = 76.0 px`) |

---

## 5. Sprite Scale and Overlap Settings

- **Approved Assets Used:** `main_cloud_01_towering_cumulus.png` (`144x92`), `main_cloud_02_sweeping_bank.png` (`160x84`), `main_cloud_03_asymmetrical_cluster.png` (`136x88`).
- **Scale Range:** `0.85x` to `1.15x` (Level A `1.00–1.15`, Level B `0.86–1.12`, Level C `0.85–0.96`), with `TEXTURE_FILTER_NEAREST`.
- **Orientation:** `flip_h = false`, `rotation = 0.0` on all instances to preserve consistent upper-left lighting.
- **Depth Ordering:** `C13ClusterCloudSea.z_index = 6`, `y_sort_enabled = true` (above `FogTileMapLayer` at `z_index = 5`, below `CursorHighlight` at `z_index = 10` and `HUD` `CanvasLayer`).

---

## 6. DayPhase Tint Settings (Authoritative `TimeManager` Driven)

A lightweight shared `CanvasItem` `ShaderMaterial` applies a non-destructive luminance-weighted lift (`smoothstep(0.08, 0.55, lum)`) plus `tint_rgb` derived from `TimeManager.get_day_phase_for_hour(hour)`, keeping `#0E1322` bases anchored while lifting midtones/highlights and clamping output `<= 0.88` (no pure white clipping):

| `TimeManager.DayPhase` | Test Time | `tint_rgb` | `mid_lift` | `highlight_gain` | `alpha_mult` |
|---|---|---|---|---|---|
| `DAWN` | `06:00` | `(0.98, 1.01, 1.08)` | `0.14` | `1.14` | `0.96` |
| `DAY` | `12:00` | `(1.04, 1.08, 1.14)` | `0.22` | `1.18` | `0.97` |
| `DUSK` | `18:30` | `(0.88, 0.96, 1.26)` | `0.18` | `1.16` | `0.97` |
| `NIGHT` | `22:00` | `(0.94, 0.98, 1.12)` | `0.20` | `1.16` | `0.97` |

---

## 7. Instance Counts and Performance Observations

- **Total Cloud Instances (`128x128` map):** `435` (`Level A: 74`, `Level B: 312`, `Level C: 49`)
- **Kind Distribution:** `146` Cloud 01 / `145` Cloud 02 / `144` Cloud 03
- **Visible in Camera (`1280x720`, `1.5x` zoom):** `52` (Cam 1 — Settlement + Frontier) / `58` (Cam 2 — Deep Cloud Sea)
- **Initialization Time (`_populate_organic_clusters`):** `233.8 ms` (one-time deterministic generation; `0 ms` per-frame placement cost, no `_process()` loop).

---

## 8. Screenshot Evidence & 9. Comparison with C1.2

- **Day 12:00 (Cam 1 — Settlement + Frontier):** `c1_3_day_1200_cam1.png` — Visibly brighter, crisp slate-blue volume compared to `c1_2_balanced_day_1200.png`, with organic cluster banks replacing staggered lattice rows.
- **Dawn 06:00 / Dusk 18:30 / Night 22:00 (Cam 1):** `c1_3_dawn_0600_cam1.png`, `c1_3_dusk_1830_cam1.png`, `c1_3_night_2200_cam1.png` — Smooth atmospheric consistency with `DayNightModulate`; Dusk avoids muddy orange via cool-violet counter-tint; Night retains dark navy identity while keeping cloud volume readable.
- **Deep Sea (Cam 2, Day 12:00):** `c1_3_day_1200_cam2_deep_sea.png` — Multi-cloud overlapping banks separated by natural dark-sky channels.
- **Frontier & Close-Up Overlap:** `c1_3_frontier_view.png`, `c1_3_closeup_overlap.png` — A2 Organic Pixel-Mist Fringe intact; zero thick black seams; zero clouds over `VISIBLE` or `EXPLORED` terrain.

---

## 10. Remaining Visual Weaknesses

1. **Frontier Gap Buffer:** Because only the three `136–160px` Main Cloud Masses are used, the 9-point `UNEXPLORED` guard leaves a ~1–1.5 tile dark buffer along parts of the explored diamond edge; future **Secondary Lobes** and **Wisps** (once authorized) can tuck closer to the frontier.
2. **Non-Integer Scale Micro-Stepping:** Subtle scale variation (`0.85x–1.15x`) introduces minor pixel-size variance between neighboring clouds under nearest-neighbor filtering (acceptable at `1.5x` gameplay zoom, slightly noticeable at `2.25x` close-up).

---

## 11. Explicit Confirmation

- **No production integration occurred:** `FogOfWar`, `FogCloudLayer`, `WorldView`, and `SaveManager` were not modified for C1.3.
- **No Git commit, stage, or push occurred.**
