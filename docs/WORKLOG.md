# KINGDOMS UNBOUND — DEVELOPMENT WORKLOG

## [2026-10-12] Milestone 1: Visual Design & Projection Alignment (Documentation Only)

### Context & Objective
Before starting autonomous development under `MASTER_PROMPT.md`, the visual direction was finalized and formalized across authoritative specifications based on the reference artwork `docs/reference/kingdom_visual_reference.png`.

### Completed Work
1. **Authoritative Perspective Specification:**
   - Established the mandatory visual direction: 2D isometric / dimetric, three-quarter top-down pixel art with 2:1 slope (~26.565°).
   - Flat overhead / straight top-down (90° bird's-eye) perspective is explicitly prohibited.
   - Buildings must show visible rooftops (tilted planes facing NW/NE) and front-facing facades (walls facing SW/SE).
2. **Tile Size Evaluation & Decision:**
   - Evaluated 16×8 px diamond (too small, causes visual noise and unreadable textures) and 64×32 px diamond (excessive sprite drawing workload, poor viewport framing at 1080p).
   - Formally standardized on **32 × 16 pixel diamond ground tiles** (2048 × 1024 px world span for a 64×64 grid), providing ideal pixel density, optimal camera framing at 1080p/720p, and crisp 2:1 pixel steps.
3. **Strict Coordinate Decoupling:**
   - The logical 64×64 grid (`Vector2i`) remains pure discrete integer simulation data (unaware of screen pixels, camera zoom, or rendering offsets).
   - The presentation layer projects `(grid_x, grid_y)` to continuous pixel screen coordinates `(screen_x, screen_y)`.
4. **Depth / Y-Sorting Architecture:**
   - Enforced Godot 2D `y_sort_enabled = true` on world parent containers and entity layers.
   - Mandated that every entity node anchor/pivot must be positioned strictly at its ground-contact plane (citizen feet, tree trunk base, building footprint center/base).
5. **Asset Style Guide Creation:**
   - Authored `docs/ASSET_STYLE_GUIDE.md` covering projection geometry, tile dimensions, sprite scales, building footprints (1×1, 2×2, 3×3 diamonds), 27-color core palette, NW directional lighting, selective outlines, animation frame counts, and Godot 4 import settings (Nearest-neighbor, lossless, pixel snapping).
6. **Visual-Validation Gate:**
   - Instituted a mandatory Visual-Validation Gate requiring a dedicated test scene (`res://scenes/test/visual_validation_test.tscn`) verifying terrain, trees, building with visible roof/facade, one moving citizen, diamond grid cursor highlighting, and flawless Y-sorting before producing or integrating large asset collections.
7. **Document Synchronization:**
   - Updated `docs/GDD.md` and `MASTER_PROMPT.md`.

---

## [2026-10-12] Milestone 2: Document Consistency Review & Technical Alignment

### Context & Objective
Rigorous consistency review of all specification documents (`docs/GDD.md`, `MASTER_PROMPT.md`, `docs/ASSET_STYLE_GUIDE.md`, `docs/GDD_REVIEW.md`, `docs/WORKLOG.md`, `AGENTS.md`, and `START_HERE.txt`) to eliminate mathematical ambiguities, reconcile discrepancies, and ensure full implementation readiness.

### Inconsistencies Discovered & Resolutions
1. **Screen-to-Grid Inverse Mapping Inconsistency:**
   - *Issue:* The previous formula used independent `floor()` operations without a $+0.5$ half-tile offset (`floor((screen_x/16 + screen_y/8)/2)`), which incorrectly shifted the tile origin to the top vertex $(0, -8)$ and mapped upper-left interior points of cell $(0, 0)$ to $(-1, 0)$ or $(-1, -1)$. Furthermore, conversion from global mouse coordinates to map-local space was not explicitly stated.
   - *Resolution:* Implemented the mathematically exact transformation using continuous axis coordinates $u = \text{local\_x}/32 + \text{local\_y}/16$ and $v = \text{local\_y}/16 - \text{local\_x}/32$, resolving cells via $\lfloor u + 0.5 \rfloor$ and $\lfloor v + 0.5 \rfloor$. Documented conversion from viewport mouse to map-local space via `tile_map_layer.to_local(mouse_pos)`, documented native Godot 4 `TileMapLayer.local_to_map()` and `map_to_local()` APIs, unified cursor highlight and building placement cell resolution, established map-boundary validation (`0 <= x, y < 64`), and added a comprehensive 13-case validation table across tile centers, off-center interiors, vertices, adjacent cells, and out-of-bounds positions.
2. **Palette-Count Inconsistency:**
   - *Issue:* `docs/WORKLOG.md` erroneously referenced a "40-color master palette", whereas `docs/ASSET_STYLE_GUIDE.md` specified exactly 27 hex color swatches across 5 material ramps.
   - *Resolution:* Standardized on the documented 27 swatches as the authoritative **27-Color Core Fantasy Palette**. Updated `docs/ASSET_STYLE_GUIDE.md` and `docs/WORKLOG.md` accordingly. Added a palette discipline rule specifying that any later secondary tones must interpolate within these 5 ramps rather than introducing arbitrary colors.
3. **Citizen Sprite Specification Variations:**
   - *Issue:* `docs/GDD.md`, `MASTER_PROMPT.md`, and `docs/ASSET_STYLE_GUIDE.md` used slightly varying dimension figures and conflated canvas frame boundaries with visible figure heights.
   - *Resolution:* Established a unified, four-part citizen specification:
     - *Default Sprite Canvas:* 24 × 32 px per frame.
     - *Visible Figure Dimensions:* 12–16 px wide by 22–26 px tall (leaving vertical and horizontal breathing room for hats, bobbing, and tools without canvas distortion).
     - *Ground-Contact Pivot:* `Vector2(12, 30)` within canvas.
     - *World-Space Footprint & Y-Sorting Anchor:* 1×1 logical cell (`Vector2i`), entity node at `map_to_local(cell)`, sprite texture offset at `Vector2(-12, -30)` for exact foot Y-sorting.
     - *Flexibility Clause:* Explicitly declared as a proposed default standard that can be adjusted for non-standard units (mounted units, banners, siege gear) when justified.
4. **Phase Outline Alignment (GDD 0–8 vs. Master Prompt 0–9):**
   - *Issue:* `docs/GDD.md` outline listed 9 phases (Giai đoạn 0–8) while `MASTER_PROMPT.md` outlined 10 phases (Phases 0–9).
   - *Resolution:* Clarified that GDD Giai đoạn 0–8 represents the high-level Game Design Roadmap, while Master Prompt Phases 0–9 represents the operational Technical Execution Workflow. GDD Giai đoạn 7 ("Chiến thắng, sụp đổ và save/load") is intentionally divided into two sequential engineering phases: Phase 7 (Population growth, crisis, prosperity victory, collapse) and Phase 8 (Robust Save/Load & persistence hardening) to isolate data serialization and prevent duplication bugs. Added explicit cross-reference mapping tables to `docs/GDD.md` (Section 18.0), `MASTER_PROMPT.md` (Development Strategy), and `docs/GDD_REVIEW.md` (Section 8).
5. **Path and Filename Consistency:**
   - *Issue:* `docs/GDD_REVIEW.md` referenced `Kingdoms_Unbound_AI_Master_Prompt.md`, which differed from the root file `MASTER_PROMPT.md`. `MASTER_PROMPT.md` line 55 omitted `docs/` prefixes on some document references.
   - *Resolution:* Standardized all references to `MASTER_PROMPT.md` and ensured all documentation paths explicitly include the `docs/` folder prefix.

### Files Changed / Modified
- `docs/ASSET_STYLE_GUIDE.md` (Updated Sections 3.1, 4.2, 4.2.1, 6.1)
- `docs/GDD.md` (Updated Sections 3.1, 18.0)
- `MASTER_PROMPT.md` (Updated Ambiguity references, Phase Mapping subsection, Architecture Rules, Asset Pipeline)
- `docs/GDD_REVIEW.md` (Updated Section 8)
- `docs/WORKLOG.md` (Updated with Milestone 2 review and reconciliation)

### Validations Performed & Results
- **Coordinate Mathematics Validation:** Verified all 13 coordinate test cases mathematically:
  - Centers: $(0, 0) \to (0, 0)$; $(16, 8) \to (1, 0)$; $(-16, 8) \to (0, 1)$; $(0, 16) \to (1, 1)$; $(0, 1008) \to (63, 63)$. All passed.
  - Off-center interiors: $(-8, 0) \to (0, 0)$; $(0, -4) \to (0, 0)$; $(8, 0) \to (0, 0)$; $(0, 4) \to (0, 0)$. All passed.
  - Vertices: $(0, -8) \to (0, 0)$ (half-open boundary).
  - Out-of-bounds: $(0, -8.1) \to (-1, -1)$; $(-32, 0) \to (-1, 1)$; $(0, 1024) \to (64, 64)$. All correctly caught by boundary validation.
- **Palette Swatch Count:** Verified exactly 27 hex codes across 5 categories in `docs/ASSET_STYLE_GUIDE.md`: Foliage (6), Earth (6), Stone (6), Water (5), Accents (4). Sum = 27.
- **Cross-Document Check:** Verified zero broken markdown headings, zero escaped formatting markers (`\#`, `\*\*`), and zero contradictory paths.
- **Implementation Isolation:** Verified `git status` confirming 0 gameplay scripts, 0 scenes, 0 shaders, 0 assets, and 0 engine configs (`project.godot`) were created or altered.

### Outstanding Issues & Conflicts
- None. All specifications are mutually consistent, mathematically validated, and ready for execution.

### Next Exact Step
- Wait for user confirmation.
- When instructed to start development, initiate **Phase 0** as specified in `MASTER_PROMPT.md`.
