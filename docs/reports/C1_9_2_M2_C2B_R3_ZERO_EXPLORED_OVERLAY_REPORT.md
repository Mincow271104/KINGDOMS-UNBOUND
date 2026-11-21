# C1.9.2 M2-C2B-R3 — Explored Terrain Visual Simplification (Zero Overlay Experiment) Report

**Date:** 2026-11-16  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** Isolated visual experiment & safety validation (`0` production files modified)  
**Engine:** Godot `v4.7.stable.official.5b4e0cb0f` (`D3D12 12_0 - Forward+`)

---

## 1. Baseline & Git Preservation Evidence

- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Pre-existing dirty-file inventory (`git status --short`):** `448` modified/untracked entries preserved untouched.
- **Production changes in R3:** **0** (`FogOfWar`, `SaveManager`, `world_view.gd`, production shaders, and legacy fog layers untouched).

---

## 2. Exact Variant A Shader Parameters (`M_D` Baseline)

- Preview configuration (shared by A & B): `world_seed = 12345`, `Town Hall = (63, 62)`, `preview_radius = 350.0 px`, `core_radius = 200.0 px`, `Day` (`12:00`), identical camera.
- Variant A (`M_D`) parameters:
  - `mist_col = vec3(0.14, 0.20, 0.28)`
  - `mist_alpha = (0.16 + 0.08 * bank) * (1.0 - vis_factor) * (1.0 - unexp_factor) * (1.0 - cloud_alpha)`
  - `vis_factor = smoothstep(0.00, 0.98, vis_cov + (bank - 0.48) * 0.62)`

---

## 3. Exact Variant B Shader Behavior (Zero Explored Overlay)

- Isolated test-only shader override on `CloudSeaComposite`:
  - `mist_alpha` removed completely (`total_alpha = clamp(cloud_alpha, 0.0, 1.0)`).
  - `VISIBLE`: clear (`discard` when `total_alpha < 0.005`).
  - `EXPLORED_NOT_VISIBLE`: `unexp_factor = 0.0` -> `cloud_alpha = 0.0` -> `discard`, leaving remembered terrain natural with zero dark overlay or artificial border.
  - `UNEXPLORED`: unchanged C1.9.1 cloud sea & preview envelope.

---

## 4. Before / After Screenshots & 5. Zoom Comparisons

All captures are stored in conversation scratch `m2_c2b_r3_zero_overlay/`:
- **Main comparison (`1.0x`):** `A_md_100x.png` vs `B_zero_100x.png`
- **Zoom `0.75x`:** `A_md_075x.png` vs `B_zero_075x.png`
- **Zoom `1.5x`:** `A_md_150x.png` vs `B_zero_150x.png`
- **Coastline + explored strip (`1.0x`):** `A_coast_explored_100x.png` vs `B_coast_explored_100x.png`

---

## 6. Gameplay Visibility Safety Results by Category (Under Variant B)

| Category | `VISIBLE` | `EXPLORED_NOT_VISIBLE` | `UNEXPLORED` | Source / Notes |
|---|---|---|---|---|
| **Resource nodes (`prop_nodes_by_cell`)** | Visible (`1`) | Visible (`1`, per existing `is_explored` rule) | **Hidden** (`visible == false`) | Verified with live scene props |
| **Points of interest (`poi_nodes_by_id`)** | — | — *(none inside test circle)* | **Hidden** (`visible == false`) | Verified with live POIs in `UNEXPLORED` (`is_explored` rule unchanged) |
| **Wildlife (`wildlife_mgr`)** | Visible (`1`) | **Hidden** (`visible == false`) | **Hidden** (`visible == false`) | Verified with live `WildlifeActor` nodes |
| **Buildings (`buildings_container`)** | Visible (`8/8`) | — | — | Verified with all 8 live starter buildings |
| **Monsters (`monster_mgr`)** | **Unverified (live)** | **Unverified (live)** | **Unverified (live)** | `0` live monsters spawned at Day 1 start on seed `12345` |
| **Enemy military (`enemy_military_mgr`)** | **Unverified (live)** | **Unverified (live)** | **Unverified (live)** | `0` live enemies spawned at Day 1 start on seed `12345` |

---

## 7. FogOfWar State Immutability Results

- `FOG_BYTES_IDENTICAL = true`: `_fog_state_bytes` (`32 KB`, `128×128` `FORMAT_R8`) was byte-for-byte identical before and after Variant B.

---

## 8. Performance Measurements

- No new textures, no new `SubViewport`s, no extra GPU passes, no per-frame CPU work.
- 20-frame average frame time (D3D12):
  - **Variant A (`M_D`):** `6.119 ms` (first run `5.883 ms`)
  - **Variant B (Zero Overlay):** `5.985 ms` (first run `5.972 ms`)
  - Delta: `< 0.14 ms` (within frame-to-frame variance).

---

## 9. Visual Advantages & Disadvantages

- **Variant A (`M_D`):**
  - *Advantage:* Preserves a subtle visual distinction between `VISIBLE` and `EXPLORED_NOT_VISIBLE`.
  - *Disadvantage:* A faint dark rounded-rectangular shadow around the settlement remains perceptible on grass.
- **Variant B (Zero Overlay):**
  - *Advantages:* Completely eliminates the dark rectangular frame around the kingdom; explored terrain looks completely natural; `UNEXPLORED` cloud sea remains prominent and unchanged.
  - *Disadvantage:* On the main map alone, `EXPLORED_NOT_VISIBLE` terrain brightness is indistinguishable from `VISIBLE` terrain (players still see the difference on the minimap and via hidden dynamic entities like wildlife/enemies).
  - *Smallest alternative if a cue is later desired:* Keep `EXPLORED_NOT_VISIBLE` overlay-free by default, or use an unobtrusive unit/building sight-range indicator rather than a Manhattan-grid overlay.

---

## 10. Exact Files Modified and Created

- **Modified production files:** **None (`0`)**.
- **Created in workspace:** `docs/reports/C1_9_2_M2_C2B_R3_ZERO_EXPLORED_OVERLAY_REPORT.md` (this report).
- **Isolated scratch artifacts:** `experiment_r3_zero_overlay.gd` and `m2_c2b_r3_zero_overlay/*.png` in conversation scratch directory.

---

## 11. Recommended Minimal Production Change (Not Applied Yet)

In `shaders/fog/cloud_sea_composite.gdshader`, remove `mist_alpha` so `total_alpha = clamp(cloud_alpha, 0.0, 1.0)` (and `COLOR = vec4(cloud_col, cloud_alpha)`), leaving `fog_state_tex` / `transition_tex` driving `unexp_factor` cleanly for `UNEXPLORED` vs explored/visible terrain.

---

## 12. Final Verdict

**READY** — Variant B cleanly eliminates the dark rectangular frame with zero performance penalty and zero entity visibility regression on all verified Day-1 categories (with live monsters/enemies noted as unverified at Day-1 start). Ready for owner decision on whether to adopt Variant B (Zero Overlay) or Variant A (`M_D`) in the next step.
