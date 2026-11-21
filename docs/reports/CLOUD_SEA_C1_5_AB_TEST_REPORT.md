# KINGDOMS UNBOUND — C1.5 In-Game Cloud A/B Visual Evaluation Report

**Milestone:** C1.5 — Controlled In-Game A/B Visual Evaluation (Prototype Only)  
**Date:** 2026-11-15  
**Engine:** Godot 4.7 (`Forward+`, `TEXTURE_FILTER_NEAREST`)  
**Status:** Complete — Awaiting Owner Decision (No Production Integration Performed)

---

## 1. Executive Summary

This report documents a controlled in-game A/B visual comparison inside the actual `WorldView` gameplay environment of **KINGDOMS UNBOUND**:

- **Version A (C1.3 Baseline):** Clustered organic cloud sea using the three C1.1 refined Main Cloud Mass sprites (`main_cloud_01_towering_cumulus.png`, `main_cloud_02_sweeping_bank.png`, `main_cloud_03_asymmetrical_cluster.png`).
- **Version B (C1.4 Morphology):** Simplified horizontal cloud morphology using the three C1.4 refined sprites (`cloud_a_long_layered_bank.png`, `cloud_b_broad_cumulus.png`, `cloud_c_wind_swept_extension.png`).

### Key Takeaway
- **Version A** provides richer pixel-art internal texture and fuller atmospheric density around the settlement and across the deep cloud sea at `1.5x` gameplay zoom, matching the pixel-art detail density of the Town Hall, houses, trees, and terrain. However, its many small rounded lobes can still look slightly busy/lumpy under `2.25x` close-up inspection.
- **Version B** achieves cleaner macro silhouettes, stronger horizontal bank flow (`Cloud A` and `Cloud C`), and eliminates the "pile of rocks" cluster silhouette problem. However, in-game at `1.5x` and `2.25x` zoom, its internal shading is noticeably smoother and simpler than the surrounding game art—especially `Cloud B`—and its lower sprite count (`308` vs `388`) leaves slightly wider dark gaps near the frontier.
- **Recommendation:** **Select Version A as the current in-game atmospheric winner for gameplay-scale visual cohesion**, OR **authorize a targeted C1.6 hybrid refinement** that pairs Version B's (`C1.4`) elongated horizontal bank silhouettes with medium-scale internal pixel-art billow texture (5–8 medium lobes rather than 30+ tiny puffs or smooth bands) before moving to production integration.

---

## 2. Experimental Setup & Controlled Conditions

Both versions were evaluated in the same automated Godot 4.7 test harness (`scratch/c1_5_ab_test/run_c1_5_ab_test.gd`) under identical engine, lighting, camera, and fog conditions:

- **Scene / World:** `WorldView` (`128x128` isometric map, deterministic seed `12345`)
- **Resolution:** `1280x720`
- **Camera Zooms:** `1.5x` (gameplay views 1, 2, 4, and post-reveal) and `2.25x` (close-up view 3)
- **Time of Day / Calibration:** Day `12:00` (`DayPhase.DAY`) with identical `ShaderMaterial` day calibration and `TEXTURE_FILTER_NEAREST`
- **Initial Fog State:** Default `center_spawn` territory plus a secondary scout pocket at `spawn + Vector2i(8, -4)` (radius `4`)
- **Exploration Dispersal Test:** `fog_of_war.reveal_circle(spawn + Vector2i(14, 6), 5)` followed by `wv._sync_full_fog_layer()` and full cloud rebuild
- **Overlap Verification:** Stride-4 opaque-pixel footprint sampling across every placed `Sprite2D` (`alpha > 0.1`) checked against `FogOfWar.is_unexplored(cell)` both before and after `reveal_circle`

---

## 3. Asset Inventory Compared

| Version | Asset File | Dimensions | Role |
|---|---|---:|---|
| **Version A (C1.3)** | `scratch/c1_1_refined/main_cloud_01_towering_cumulus.png` | `144x92` | Primary towering cumulus mass |
| **Version A (C1.3)** | `scratch/c1_1_refined/main_cloud_02_sweeping_bank.png` | `160x84` | Horizontal sweeping cloud bank |
| **Version A (C1.3)** | `scratch/c1_1_refined/main_cloud_03_asymmetrical_cluster.png` | `136x88` | Asymmetrical cluster mass |
| **Version B (C1.4)** | `scratch/c1_4_morphology/cloud_a_long_layered_bank.png` | `196x86` | Primary long layered bank (46% weight) |
| **Version B (C1.4)** | `scratch/c1_4_morphology/cloud_b_broad_cumulus.png` | `160x108` | Selective cumulus height (30% weight) |
| **Version B (C1.4)** | `scratch/c1_4_morphology/cloud_c_wind_swept_extension.png` | `176x52` | Restrained wind-swept bridge (24% weight) |

---

## 4. Quantitative Metrics Observed

Measured directly from Godot 4.7 headless/rendered execution of `run_c1_5_ab_test.gd`:

| Metric | Version A (C1.3) | Version B (C1.4) |
|---|---:|---:|
| **Total Placed Cloud Sprites (Initial)** | `388` | `308` |
| **Total Placed Cloud Sprites (After `reveal_circle`)** | `386` | `307` |
| **Placement Build Time (`init_ms`)** | `356.32 ms` | `340.90 ms` |
| **Visible Sprites — View 1 (Settlement Frontier, 1.5x)** | `40` | `30` |
| **Visible Sprites — View 2 (Deep Cloud Sea, 1.5x)** | `48` | `40` |
| **Visible Sprites — View 3 (Close-Up, 2.25x)** | `24` | `19` |
| **Visible Sprites — View 4 (Exploration Boundary, 1.5x)** | `41` | `33` |
| **Explored-Tile Pixel Leaks (Before Reveal)** | `0` | `0` |
| **Explored-Tile Pixel Leaks (After Reveal)** | `0` | `0` |

---

## 5. View 1 — Settlement & Exploration Frontier (`1.5x`)

Side-by-side comparison (`AB_settlement_comparison.png`, Version A left, Version B right):

![AB Settlement Comparison](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_ab_test/AB_settlement_comparison.png)

- **Version A (Left):** Forms a dense, atmospheric framing belt around the settlement's A2 pixel-mist frontier (`40` visible sprites). Internal pixel-art shading and multi-lobe highlights harmonize naturally with the Town Hall, cottages, pine trees, and stone nodes.
- **Version B (Right):** Forms sleeker horizontal banks (`30` visible sprites) with a calmer silhouette, but leaves noticeably wider dark unexplored gaps on the left and right edges of the settlement, and its smoother surfaces contrast slightly with the crisp pixel-art buildings.

---

## 6. View 2 — Deep Unexplored Cloud Sea (`1.5x`)

Side-by-side comparison (`AB_deep_sea_comparison.png`, Version A left, Version B right):

![AB Deep Sea Comparison](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_ab_test/AB_deep_sea_comparison.png)

- **Version A (Left):** Reads as a rich, textured dark-fantasy cloud sea (`48` visible sprites) with strong overlapping depth and varied cumulus silhouettes, though a few adjacent clusters still show repetitive small-lobe textures.
- **Version B (Right):** Achieves noticeably better horizontal continuity where `Cloud A` and `Cloud C` connect (`40` visible sprites), successfully avoiding the rocky cluster look. However, `Cloud B` stands out as overly rounded and smooth compared to the surrounding atmospheric mood.

---

## 7. View 3 — Close-Up Pixel Inspection (`2.25x`)

Side-by-side comparison (`AB_closeup_comparison.png`, Version A left, Version B right):

![AB Closeup Comparison](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_ab_test/AB_closeup_comparison.png)

- **Rendering Integrity:** Both versions render with crisp nearest-neighbor pixels, clean alpha edges, and zero tiling seams or bounding-box artifacts.
- **Version A (Left):** Rich internal pixel-art puff detail holds up well against the game's pixel density, though up close the dense cluster of small rounded bumps feels somewhat busy.
- **Version B (Right):** Very clean tonal bands and soft tapered undersides, but up close `Cloud B` looks overly simplified/smooth (almost vector-shaded) and shows a minor `2x2` dark pixel spot near its upper dome.

---

## 8. View 4 — Exploration Boundary & Scout Pocket (`1.5x`)

Side-by-side comparison (`AB_exploration_comparison.png`, Version A left, Version B right):

![AB Exploration Comparison](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_ab_test/AB_exploration_comparison.png)

- Both versions respect the A2 frontier and the secondary scout pocket cleanly with `leaks_before=0`.
- Version A hugs the frontier slightly more evenly due to its higher local sprite density (`41` vs `33` visible sprites), whereas Version B preserves a cleaner negative-space separation around the revealed pocket.

---

## 9. Exploration Dispersal Verification (`reveal_circle`)

After calling `fog_of_war.reveal_circle(spawn + Vector2i(14, 6), 5)` and syncing the fog layer:

| Version A (`A_exploration_after_reveal.png`) | Version B (`B_exploration_after_reveal.png`) |
|---|---|
| ![A After Reveal](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_ab_test/A_exploration_after_reveal.png) | ![B After Reveal](file:///C:/Users/HP/.gemini/antigravity/brain/a85aee3a-3169-4df6-8f70-2291df8ba327/scratch/c1_5_ab_test/B_exploration_after_reveal.png) |

- **Version A:** Total placed sprites updated cleanly from `388` to `386`, `leaks_after=0`, and the newly revealed 5-tile diamond pocket is 100% clear of cloud pixels.
- **Version B:** Total placed sprites updated cleanly from `308` to `307`, `leaks_after=0`, and the newly revealed pocket is 100% clear of cloud pixels.

---

## 10. Visual Critique: Strengths & Weaknesses

### Version A (C1.3)
- **Strengths:** Matches KINGDOMS UNBOUND's pixel-art detail level; fuller cloud-sea coverage; strong atmospheric depth and rim highlights against the dark unexplored void.
- **Weaknesses:** Individual sprites still contain many small rounded lobes that can read as busy/pebbly up close; slightly higher sprite count (`388` vs `308`).

### Version B (C1.4)
- **Strengths:** Eliminates the "rock pile" morphology; `Cloud A` and `Cloud C` create genuine horizontal bank flow; lower sprite count (`308`) and slightly faster build (`340.90 ms`).
- **Weaknesses:** Internal shading is too smooth/simple next to detailed pixel-art buildings and trees; `Cloud B` reads as an isolated smooth dome; lower density leaves wider dark gaps around the frontier.

---

## 11. Performance & Architecture Notes

- Both versions build in ~`340–356 ms` for a `128x128` world and use `308–388` `Sprite2D` nodes total (`19–48` visible per viewport).
- No production files (`FogOfWar`, `FogCloudLayer`, `WorldView`, `SaveManager`, `TerritoryManager`, `FogTileMapLayer`, `assets/fog/*`) were modified during C1.5.

---

## 12. Evaluation Matrix (1–5 Scale)

| Criterion | Version A (C1.3) | Version B (C1.4) | Notes |
|---|---:|---:|---|
| 1. Reads as Clouds (vs. Rocks/Lumps) | 3 | **4** | B removes small rock-like lobes; A still has subtle pebble-like clusters up close. |
| 2. Horizontal Bank Continuity | 3 | **4** | B's `Cloud A` & `Cloud C` flow horizontally much more naturally. |
| 3. Pixel-Art Style Cohesion with Game | **5** | 3 | A's internal pixel texture matches buildings/trees; B looks too smooth/simple. |
| 4. Depth, Volume & Rim Lighting | **4** | 3 | A has stronger internal volumetric contrast; B feels flatter in deep sea. |
| 5. Frontier & Settlement Framing | **4** | 3 | A frames the settlement more evenly; B leaves wider dark gaps at edges. |
| 6. Deep Cloud Sea Atmosphere | **4** | 3 | A feels richer and more mysterious across wide unexplored expanses. |
| 7. Close-Up (`2.25x`) Pixel Quality | 3 | 3 | A is crisp but busy; B is clean/smooth but overly simple (`Cloud B` spot). |
| 8. Exploration Boundary Precision | **5** | **5** | Both achieve `0` pixel leaks before and after `reveal_circle`. |
| 9. Runtime & Node Efficiency | 4 | **5** | B uses `20.6%` fewer sprites (`308` vs `388`) and builds slightly faster. |
| 10. Overall Gameplay Readiness | **4** | 3 | A works better out-of-the-box with game art; B needs internal texture pass. |
| **Total Score (out of 50)** | **39** | **36** | **Version A leads overall; hybrid of B's shapes + A's texture is ideal.** |

---

## 13. Next-Step Recommendation

1. **Option 1 (Fastest Path):** Proceed to production integration planning using **Version A (C1.3)** as the baseline visual style, since it scores higher (`39/50` vs `36/50`) and integrates seamlessly with the game's pixel-art buildings and terrain.
2. **Option 2 (Highest Visual Ceiling — Recommended if time permits):** Run a focused **C1.6 Hybrid Refinement** on Version B's three sprites (`cloud_a`, `cloud_b`, `cloud_c`)—preserving their elongated horizontal silhouettes while adding medium-scale internal pixel-art billow texture (and fixing `Cloud B`'s overly round dome and `2x2` upper spot)—to capture both Version B's horizontal flow (`308` sprites) and Version A's pixel-art richness.

*No production integration or further milestone work has been started pending owner review.*
