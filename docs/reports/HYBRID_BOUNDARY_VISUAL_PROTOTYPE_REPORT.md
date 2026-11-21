# Hybrid Visual Boundary System — Prototype Report

**Status:** VISUAL PROTOTYPE ONLY (no production code, test code, save schema, or gameplay logic modified)  
**Engine:** Godot 4.7 (`Godot_v4.7-stable_win64_console.exe`, D3D12 Forward+, `1280x720`, `world_seed = 12345`)  
**Prototype Script (Isolated Scratch):** `C:\Users\HP\.gemini\antigravity\brain\a85aee3a-3169-4df6-8f70-2291df8ba327\scratch\prototype_hybrid_boundaries.gd`

---

## 1. Visual Alternatives & Prototype Results

### Prototype A — Fog of War (`32×16` Isometric Frontier)
Generated a 16-tile cardinal-neighbor bitmask atlas (`0..15`: `N/TR=1, E/BR=2, S/BL=4, W/TL=8`) on `FogTileMapLayer` (`z_index = 5`) without altering `FogOfWar._grid` or `reveal_circle()`:
- **Variant A1 — Bayer 4×4 Dithered Fade (`proto_after_a1_bayer_day_1200.png`):**
  - Crisp pixel-art ordered dithering along exposed `UNEXPLORED ↔ EXPLORED/VISIBLE` edges. Very clean, though the regular checkerboard pattern is slightly geometric.
- **Variant A2 — Organic Pixel-Mist Fringe (`proto_after_a2_organic_day_1200.png`, `proto_after_a2_organic_night_2200.png`, `proto_after_a2_unselected_day_1200.png`):**
  - Combines deterministic pixel hash + Bayer threshold with a translucent (`0.72`) mid-band. Softens the sawtooth diamond tips naturally around both convex and concave corners (verified with an intersecting secondary lobe at `(55, 57)`).
- **Recommended:** **Variant A2 (Organic Pixel-Mist Fringe)**.

### Prototype B — Territory Boundary (`_territory_overlay`)
Replaced per-cell `32×16` interior grid outlines with:
- Subtle unified translucent fill (`Color(0.2, 0.72, 0.95, 0.08)`).
- **Outer exposed perimeter edges only** (`Color(0.35, 0.88, 1.0, 0.9)`, `2.5px`), checking the 4 cardinal neighbors of each `border_cell` via `territory_mgr.is_cell_owned()`.
- **Result:** Eliminates interior grid clutter completely while keeping exact tile ownership across convex and concave borders in both Day (`12:00`) and Night (`22:00`).
- **Recommended:** **Outer Perimeter Contour + Subtle Fill**.

### Prototype C — Building Selection (`BuildingSelectionHighlight`)
Replaced the 4 circular corner dots with:
- Thin inner royal-gold diamond (`1.5px`, `alpha 0.55`) + subtle fill (`alpha 0.14`).
- **Crisp 2:1 isometric corner brackets** (`3.0px`, `22%` edge arm length, `Color(1.0, 0.90, 0.35, 0.98)`) at all 4 diamond vertices.
- **Result:** Cleanly frames the exact `3×3` Town Hall footprint in both Day (`12:00`) and Night (`22:00`) without obscuring sprite details.
- **Recommended:** **Bracketed Isometric Footprint**.

---

## 2. Screenshot Evidence (Before & After)
All screenshots are in `C:\Users\HP\.gemini\antigravity\brain\a85aee3a-3169-4df6-8f70-2291df8ba327\scratch\`:
- `proto_before_day_1200.png` — Current baseline (`12:00`, Town Hall selected + territory grid + jagged fog).
- `proto_before_night_2200.png` — Current baseline (`22:00` Night).
- `proto_after_a1_bayer_day_1200.png` — Prototype A1 (Bayer) + B + C (`12:00` Day).
- `proto_after_a2_organic_day_1200.png` — Prototype A2 (Organic Mist) + B + C (`12:00` Day).
- `proto_after_a2_organic_night_2200.png` — Prototype A2 (Organic Mist) + B + C (`22:00` Night).
- `proto_after_a2_unselected_day_1200.png` — Prototype A2 Fog only, Town Hall unselected (`12:00` Day).

---

## 3. Relevant Implementation Files (For Future Approved Implementation)
- `scripts/world/world_view.gd` (`_setup_fog_layer`, `_sync_full_fog_layer`, incremental fog cell updates, `_on_territory_overlay_draw`)
- `scripts/world/building_selection_highlight.gd` (`_draw`)
- *(Untouched: `fog_of_war.gd`, `territory_manager.gd`, `save_manager.gd`, `time_manager.gd`)*

---

## 4. Performance Considerations
- **Fog Bitmask Atlas:** Precomputed once at startup (`512×16` RGBA8 texture, 16 tiles). Updating a revealed tile only refreshes that tile and its 4 cardinal neighbors (`O(1)` per cell).
- **Territory Perimeter:** Draws edges only for `get_border_cells()` instead of `4` polyline edges per owned cell, **reducing** draw calls significantly as territory grows.
- **Building Selection:** Fixed `4` corner brackets + `1` polyline (`O(1)`).

---

## 5. Risks & Regression Tests
- **Risks:**
  - Incremental fog updates (`update_observers` / `reveal_circle`) must refresh the 4 cardinal neighbors of newly revealed/degraded cells so bitmask edges stay in sync.
  - `BuildingSelectionHighlight` bracket arm length (`0.22`) should be tested on `1×1`, `2×2`, and `3×3` footprints so small `1×1` buildings don't look crowded.
- **Required Regression Suites (once implemented):**
  - `test_fog_of_war_reconnaissance.gd`, `test_fog_rendering.gd`, `test_fog_debug_toggle.gd`
  - `test_town_hall_territory.gd`, `test_day_night_phase2.gd`, `test_save_load.gd`, `test_all_scripts_load.gd`

---

## 6. Files Modified & Git Safety
- **Repository Code/Test Files Modified:** None (`0`).
- **Report Created:** `docs/reports/HYBRID_BOUNDARY_VISUAL_PROTOTYPE_REPORT.md`
- **Git Discipline:** No files were staged, committed, pushed, reset, stashed, or cleaned.
