# KINGDOMS UNBOUND — CITIZEN VISUAL PROPORTION TUNING REPORT
## Controlled Pixel-Art Refinement — Citizen Sprite Only

**Date:** 2026-11-12  
**Godot Target:** Godot Engine v4.7-stable (official build `5b4e0cb0f`)  
**Hardware Renderer:** D3D12 Forward+ on NVIDIA GeForce RTX 3050 Ti Laptop GPU  
**Workspace:** `E:\KINGDOMS UNBOUND\kingdoms-unbound`  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Reference HEAD:** `fa09df2fd152a874dbc26461435644ad8822c34e`  
**Backup Location:** `E:\KINGDOMS UNBOUND\_asset_backup_pre_citizen_tuning\assets\entities\`

---

## 1. Executive Summary

Following the completion of the Isometric Pixel Art Asset V2 integration, project owner gameplay testing identified that citizen characters appeared disproportionately large beside settlement buildings (Town Hall, Houses, Woodcutter, Farm, Workshop).

To resolve this visual disparity while preserving the classic 2D isometric aesthetic, a controlled pixel-art refinement was executed exclusively on `assets/entities/citizen.png`:
- The visible character artwork was reduced by **15.38% in height** and **16.67% in width** (overall ~16% visual reduction, strictly within the owner's approved 15–17% target window).
- The visible bounding box was refined from **$12 \times 26$ pixels** down to **$10 \times 22$ pixels**.
- The texture canvas remains strictly **$24 \times 32$ pixels**.
- The horizontal center ($x = 11.5$) and ground-contact baseline ($y = 30$, shadow at $y = 31$) were preserved with sub-pixel precision, requiring zero changes to engine node transforms, collision shapes, pathfinding, or the WorldView sprite offset `Vector2(-12.0, -30.0)`.
- All 15 original RGBA palette tones were preserved with zero blurring, bilinear filtering, or color drift.
- Full hardware D3D12 before/after runtime visual validation was conducted across 6 scenarios (beside House, near Town Hall, gathering in plaza, Y-sorting front/behind buildings, selection/inspector UI, and standard gameplay zoom).
- All 159 project GDScript files compiled cleanly, and all persistence, simulation, and lifecycle regression tests passed with a 100% pass rate (Exit Code 0).

---

## 2. Original vs. Final Visible Dimensions

| Dimension Attribute | Original Asset | Refined Asset (Candidate 3) | Delta / Change | Ratio / Scale |
|---|:---:|:---:|:---:|:---:|
| **Canvas Dimensions** | $24 \times 32$ px | $24 \times 32$ px | 0 px | 100.0% (Invariant) |
| **Visible Width** | 12 px ($x \in [6, 17]$) | 10 px ($x \in [7, 16]$) | -2 px | **83.33% (-16.67%)** |
| **Visible Height (incl. shadow)** | 26 px ($y \in [6, 31]$) | 22 px ($y \in [10, 31]$) | -4 px | **84.62% (-15.38%)** |
| **Visible Body Height (excl. shadow)** | 24 px ($y \in [6, 29]$) | 20 px ($y \in [10, 29]$) | -4 px | **83.33% (-16.67%)** |
| **Shadow Height** | 2 px ($y \in [30, 31]$) | 2 px ($y \in [30, 31]$) | 0 px | 100.0% (Invariant) |
| **Horizontal Center ($\bar{x}$)** | 11.5 px ($(6+17)/2$) | 11.5 px ($(7+16)/2$) | 0.0 px | **Exact Match (Invariant)** |
| **Ground-Contact Pivot ($y$)** | $y = 30$ px | $y = 30$ px | 0 px | **Exact Match (Invariant)** |
| **Visible Pixel Area** | 312 px² ($12 \times 26$) | 220 px² ($10 \times 22$) | -92 px² | **70.51% (-29.49% area)** |
| **Texture UID** | `uid://coqw0ehq1uc0j` | `uid://coqw0ehq1uc0j` | Unchanged | Preserved |

---

## 3. Pixel Resizing Method & Palette Preservation

### 3.1. Technical Analysis of Downscaling
A standard naive nearest-neighbor downscaling from 12 px to 10 px width skips two fixed columns ($x=5$ and $x=11$). In a hand-crafted pixel art sprite, this naive skipping broke leg symmetry (leaving one 2px leg and one 1px leg) and displaced the eye sockets asymmetrically to the left. Furthermore, vertical naive sampling from 26 px to 22 px dropped the red collar/scarf at row 15.

### 3.2. Symmetrical Nearest-Neighbor Sampling (Candidate 3)
To ensure the character remains identifiable and aesthetically sharp at native pixel resolution:
1. **Red Hat (Rows 10–12):** Scaled from 4 rows to 3 rows. The top crown highlight, directional shadow ramp, and dark outline are preserved.
2. **Face & Eyes (Rows 13–16):** Scaled from 5 rows to 4 rows. Left hair fringe, both distinct 1px eye sockets, nose bridge, skin tone, and chin are symmetrically preserved.
3. **Red Scarf / Collar (Row 17):** Symmetrically preserved across 10 pixels ($x=7..16$), providing clean visual separation between head and torso.
4. **Blue Tunic & Shading (Rows 18–21):** Features 3-tone NW directional lighting (`#3d78a8ff`, `#2d5c88ff`, `#1e3f60ff`).
5. **Belt & Buckle (Row 20):** Dark leather belt (`#593520ff`) with a 2-pixel gold buckle (`#f2be42ff`) centered at $x=10..11$.
6. **Hands & Tunic Hem (Row 21):** Symmetrical skin-tone hands at left and right sleeve openings.
7. **Trouser Legs (Rows 22–26):** Scaled with two distinct 2-pixel legs separated by a 2-pixel central dark seam, eliminating the asymmetry of naive sampling.
8. **Boots & Shadow (Rows 27–31):** Leather boots touch down at row 29. Contact drop shadow (`#10161c5f`) is centered at $(12, 30)$ with widths of 8 px (row 30) and 6 px (row 31).

### 3.3. Complete 15-Color Authoritative Palette Verification
Zero foreign colors, blurring, or anti-aliasing artifacts were introduced. Every pixel in the refined asset maps to the original palette:

| RGBA Value | Hex Code | Visual Element |
|---|---|---|
| `(20, 24, 32, 255)` | `#141820ff` | Dark silhouette outlines and eyes |
| `(158, 52, 40, 255)` | `#9e3428ff` | Cap shadow ramp & scarf shadow |
| `(212, 86, 70, 255)` | `#d45646ff` | Cap highlight & scarf highlight |
| `(246, 198, 158, 255)` | `#f6c69eff` | Face, forehead, hands (Skin light) |
| `(217, 156, 114, 255)` | `#d99c72ff` | Cheek, jawline shadow (Skin shadow) |
| `(92, 56, 36, 255)` | `#5c3824ff` | Hair fringe (Chestnut brown) |
| `(61, 120, 168, 255)` | `#3d78a8ff` | Tunic NW light ramp (Cerulean blue) |
| `(45, 92, 136, 255)` | `#2d5c88ff` | Tunic midtone (Cobalt blue) |
| `(30, 63, 96, 255)` | `#1e3f60ff` | Tunic SE shadow ramp (Navy blue) |
| `(89, 53, 32, 255)` | `#593520ff` | Leather belt (Dark brown) |
| `(242, 190, 66, 255)` | `#f2be42ff` | Belt buckle (Gleaming gold) |
| `(74, 82, 98, 255)` | `#4a5262ff` | Trousers highlight (Slate grey) |
| `(50, 56, 70, 255)` | `#323846ff` | Trousers shadow (Dark slate) |
| `(66, 40, 24, 255)` | `#422818ff` | Boots / shoes (Boot brown) |
| `(16, 22, 28, 95)` | `#10161c5f` | Contact drop shadow (37% alpha) |

---

## 4. Foot-Anchor Alignment Verification

In KINGDOMS UNBOUND's 2:1 dimetric isometric projection:
- Ground tiles are $32 \times 16$ diamonds.
- WorldView anchors citizens via `spr.offset = Vector2(-12.0, -30.0)` with `spr.centered = false`.
- The entity's ground contact plane is $(0, 0)$ in local node coordinates (`IsoMath.map_to_local(cell)`).
- With `offset = Vector2(-12.0, -30.0)`, pixel $(12, 30)$ of the $24 \times 32$ canvas maps precisely to $(0, 0)$ in world space:
  $$\text{World } X = \text{Node } X - 12 + 12 = \text{Node } X$$
  $$\text{World } Y = \text{Node } Y - 30 + 30 = \text{Node } Y$$

Because the refined artwork preserves the horizontal center ($x = 11.5 \approx 12$) and the foot contact plane at $y = 30$, the character's feet touch the isometric diamond at the exact same sub-pixel position as before. No height jumping, floating, or ground clipping occurs.

---

## 5. Visual Proportions in the Settlement Environment

### 5.1. Proportion Relative to House ($64 \times 56$ px, 2×2 Footprint)
- **Before:** Citizen stood 26 pixels tall (nearly 47% of the total building height, and significantly taller than the house doorway). The citizen competed with the house for visual prominence.
- **After:** Citizen stands 22 pixels tall (39% of building height). The citizen's head aligns naturally with the lintel of the front porch, making the 2-story house look like a genuine dwelling structure.

### 5.2. Proportion Relative to Town Hall ($96 \times 80$ px, 3×3 Footprint)
- **Before:** Citizens grouped in front of the Town Hall covered the grand portico steps and dominated the plaza.
- **After:** Citizens appear as believable scale human inhabitants. The Town Hall retains its commanding civic stature while citizens remain clearly identifiable.

---

## 6. Before / After Runtime Hardware Visual Validation

Validation was executed live using `Godot_v4.7-stable_win64_console.exe` under the Forward+ D3D12 hardware renderer on an NVIDIA RTX 3050 Ti GPU with world seed `12345` at $1280 \times 720$ resolution:

| Validation Scenario | Description & Observations | Side-by-Side Comparison File |
|---|---|---|
| **A. Citizen beside House (2×2)** | 2 citizens positioned next to the House (one beside corner, one in front). The refined citizen matches the entrance portal height naturally. | `docs/visual_validation/citizen_tuning/comp_01_citizen_beside_house.png`<br>`docs/visual_validation/citizen_tuning/closeup_01_citizen_beside_house.png` |
| **B. Citizen near Town Hall (3×3)** | Citizen standing on the front steps of the portico. Demonstrates civic building dominance and readable scale. | `docs/visual_validation/citizen_tuning/comp_02_citizen_near_townhall.png`<br>`docs/visual_validation/citizen_tuning/closeup_02_citizen_near_townhall.png` |
| **C. Plaza Gathering** | 6 citizens gathered in the central settlement square. Group density no longer crowds or overwhelms building facades. | `docs/visual_validation/citizen_tuning/comp_03_citizens_gathering.png` |
| **D. Depth & Y-Sorting** | Citizens walking behind Town Hall roof ($y=30$), in front of portico ($y=34$), behind House roof ($y=33$), and in front of House ($y=36$). Zero flickering, sorting flawless. | `docs/visual_validation/citizen_tuning/comp_04_citizen_ysort_front_behind.png` |
| **E. Selection & Inspection UI** | Citizen clicked and selected; HUD citizen inspector opens on the right displaying name, role, hunger, fatigue, and morale. | `docs/visual_validation/citizen_tuning/comp_05_citizen_selection_inspection.png` |
| **F. Settlement Overview** | Broad settlement view at default gameplay camera zoom ($1.8\times$). Citizens remain readable, crisp, and properly proportioned across the entire settlement. | `docs/visual_validation/citizen_tuning/comp_06_settlement_overview.png` |

---

## 7. Gameplay and Architecture Invariants

This task was strictly visual. The following systems and data contracts were verified to be completely untouched:
- **Node Transform & Scale:** `Node2D.scale` remains `Vector2(1.0, 1.0)`. No fractional scaling applied.
- **Collision & Navigation:** `Navigation2D` / `AStar2D` grid paths (`Vector2i`) are 100% unaffected.
- **Selection Hitbox:** `_check_citizen_click(cell)` queries `IsoMath.grid_distance(cell, c_cell) <= 1` (grid cell distance, unaffected by sprite pixels).
- **Citizen State Machine:** `CitizenController.State` transitions (IDLE, WORKING, MOVING, HAULING, SEEKING_FOOD, RESTING) function identically.
- **Save/Load Compatibility:** Save games serialize citizen roles, stats, and cell coordinates; texture changes produce zero serialization diffs.
- **Starter & Immigrant Consistency:** `_spawn_starter_citizens()`, `_spawn_immigrant_wave()`, and `SaveManager.apply_loaded_state_to_world()` all load `res://assets/entities/citizen.png` through the unified rendering path. All citizen instances use the new refined sprite.

---

## 8. Regression Results

All test suites executed under headless Godot 4.7 passed with **Exit Code 0**:

| Suite # | Test Suite | Path | Metric | Result |
|:---:|---|---|:---:|:---:|
| 1 | Compiler & Syntax Validator | `scripts/test/test_all_scripts_load.gd` | 159 / 159 scripts compiled | **PASS (Exit 0)** |
| 2 | Persistence & Save/Load Roundtrip | `scripts/test/test_save_load.gd` | 182 / 182 assertions passed | **PASS (Exit 0)** |
| 3 | Dynamic Workplaces & Logistics | `scripts/test/test_dynamic_workplaces.gd` | 13 / 13 scenarios passed | **PASS (Exit 0)** |
| 4 | Workplace Buffer Disposition (Session 6) | `scripts/test/test_session6_workplace_buffer_disposition.gd` | 85 / 85 assertions passed | **PASS (Exit 0)** |
| 5 | Visual Asset Pack V2 Acceptance | `scripts/test/visual_asset_v2_acceptance.gd` | 5 / 5 visual steps passed | **PASS (Exit 0)** |
| 6 | Citizen Proportion Validation Harness | `scripts/test/visual_citizen_proportion_validation.gd` | 6 / 6 before/after captures passed | **PASS (Exit 0)** |

---

## 9. Backup and File Modifications

### Backup Location:
- Full pre-tuning backup preserved outside Git repository at:  
  `E:\KINGDOMS UNBOUND\_asset_backup_pre_citizen_tuning\assets\entities\`  
  Contains original `citizen.png` ($12 \times 26$ px visible) and `citizen.png.import`.

### Files Modified:
- `assets/entities/citizen.png` (Refined $10 \times 22$ px visible artwork within $24 \times 32$ px canvas)
- `docs/WORKLOG.md` (Updated with citizen proportion tuning milestone)

### Files Created:
- `docs/CITIZEN_SPRITE_SCALE_REFINEMENT_REPORT.md` (Authoritative refinement report)
- `scripts/test/visual_citizen_proportion_validation.gd` (Automated before/after visual harness)
- 14 verification and comparison screenshots in `docs/visual_validation/citizen_tuning/`:
  - `before_01_citizen_beside_house.png`
  - `before_02_citizen_near_townhall.png`
  - `before_03_citizens_gathering.png`
  - `before_04_citizen_ysort_front_behind.png`
  - `before_05_citizen_selection_inspection.png`
  - `before_06_settlement_overview.png`
  - `after_01_citizen_beside_house.png`
  - `after_02_citizen_near_townhall.png`
  - `after_03_citizens_gathering.png`
  - `after_04_citizen_ysort_front_behind.png`
  - `after_05_citizen_selection_inspection.png`
  - `after_06_settlement_overview.png`
  - `comp_01_citizen_beside_house.png` .. `comp_06_settlement_overview.png`
  - `closeup_01_citizen_beside_house.png` & `closeup_02_citizen_near_townhall.png`

---

## 10. Git Status and Worktree Preservation

- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Reference HEAD:** `fa09df2fd152a874dbc26461435644ad8822c34e`
- **Git Restrictions:**
  - Zero commits created.
  - Zero pushes initiated.
  - Zero branches created or switched.
  - Zero files staged or stashed.
  - All pre-existing user modifications and untracked files safely preserved.
