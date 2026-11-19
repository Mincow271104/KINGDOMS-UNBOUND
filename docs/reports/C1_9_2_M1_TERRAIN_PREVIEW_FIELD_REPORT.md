# C1.9.2 — M1 `TerrainPreviewField` Implementation Report

**Date:** 2026-11-16  
**Milestone:** C1.9.2 — M1 (`TerrainPreviewField` Domain & Envelope Generator)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`

---

## 1. Exact Files Created and Modified
- **Created:**
  - `scripts/world/terrain_preview_field.gd` (`class_name TerrainPreviewField`)
  - `scripts/test/test_terrain_preview_field.gd`
  - `docs/reports/C1_9_2_M1_TERRAIN_PREVIEW_FIELD_REPORT.md`
- **Modified:** None (all pre-existing production files, scenes, shaders, and assets remain untouched).

---

## 2. Final Helper API (`TerrainPreviewField`)
- **Enums & Constants:**
  - `enum SourceCategory { TOWN_HALL = 0, HUNTER_SCOUT = 1, SOLDIER = 2 }`
  - `PREVIEW_SMOOTH_K = 135.0`, `CORE_SMOOTH_K = 95.0`
  - `PREVIEW_SD_CLAMP = 300.0`, `PREVIEW_SD_RANGE = 600.0`
  - `CORE_SD_CLAMP = 200.0`, `CORE_SD_RANGE = 400.0`
  - `DEFAULT_OVAL_X = 1.18`
  - Category default radii:
    - Town Hall: `310.0` px preview / `165.0` px core
    - Hunter / Scout: `185.0` px preview / `0.0` px core
    - Soldier: `165.0` px preview / `95.0` px core
- **Configuration & Separation:**
  - `configure(width: int, height: int, seed_value: int, res_scale: int = 2, fog_of_war: FogOfWar = null) -> void`
  - `set_fog_of_war(fog_of_war: FogOfWar) -> void` (read-only reference for `B` channel `is_explored(cell)`; never mutates `FogOfWar`)
- **Source Lifecycle:**
  - `register_source(id, category, cell, preview_radius_px = -1.0, core_radius_px = -1.0, dir = Vector2.ZERO, oval_x = DEFAULT_OVAL_X) -> bool` (returns `false` on empty or duplicate ID)
  - `upsert_source(...) -> void` (idempotent add/update)
  - `update_source(id, cell, ...) -> bool` (returns `false` if ID missing)
  - `remove_source(id) -> bool`
  - `clear_sources() -> void`
  - `has_source(id) -> bool`, `get_source(id) -> Dictionary`, `get_source_ids() -> Array[String]`, `get_source_count() -> int`
- **Envelope Evaluation & Output:**
  - `rebuild_full() -> void`
  - `apply_incremental_updates() -> Rect2i`
  - `update_dirty_rect(texel_rect: Rect2i) -> void`
  - `has_pending_dirty_rect() -> bool`, `get_pending_dirty_rect() -> Rect2i`
  - `get_envelope_image() -> Image`, `get_envelope_texture() -> ImageTexture`, `get_memory_bytes() -> int`
  - `evaluate_preview_sd_at_iso(p_iso: Vector2) -> float`, `evaluate_core_sd_at_iso(p_iso: Vector2) -> float`, `is_cell_in_preview(cell: Vector2i) -> bool`

---

## 3. Source Lifecycle Design & Data Separation
- **Stable IDs:** Sources are stored by string ID (`_sources: Dictionary`) with deterministic insertion order (`_ordered_ids: Array[String]`).
- **Soldier Movement:** Calling `update_source("soldier_<id>", new_cell)` marks both the old and new influence regions dirty and replaces `center_iso` in place — old positions immediately stop contributing (zero historical trail accumulation).
- **Overlapping Source Removal:** `remove_source(id)` marks the removed source's influence region dirty and erases only that ID; remaining overlapping sources are re-evaluated cleanly in the dirty rect.
- **Map-Edge Clamping:** `_clamp_cell(cell)` clamps source cells to `[0, map_width - 1] x [0, map_height - 1]`, and dirty rects clamp to `[0, tex_width - 1] x [0, tex_height - 1]`.
- **M2 Three-Input Combination Plan:**
  1. `FogOfWar.EXPLORED` -> `B` channel (`is_explored(cell)`), plus authoritative entity/prop/POI visibility.
  2. `FogOfWar.VISIBLE` -> authoritative dynamic actor/enemy/wildlife/monster visibility in `WorldView`.
  3. `TerrainPreviewField` -> `R` (`preview_sd`) and `G` (`core_sd`) channels in `envelope_tex` driving only the `cloud_sea_envelope.gdshader` visual fade, with zero authority over gameplay discovery or entity visibility.

---

## 4. Geometry and Envelope Calculation
- **Isometric Screen-Space Metric:** Texel `(tx, ty)` maps to continuous grid `(u_grid, v_grid)` via `((tx + 0.5) / resolution_scale) - 0.5` and then to screen-space isometric coordinates via `IsoMath.HALF_WIDTH` (`16.0`) and `IsoMath.HALF_HEIGHT` (`8.0`), matching `c1_9_1_envelope_cloud.gdshader` `mask_uv`.
- **Oval & Bounded Lobe Form:** Screen-space delta `(dx / oval_x, dy)` with `oval_x = 1.18` and bounded low-frequency harmonic `1.0 + 0.045 * sin(2*ang + phase_a) + 0.035 * cos(3*ang + phase_b)` (evaluated via exact unit-vector Chebyshev identities with zero `atan2`/`sin`/`cos` in the inner loop).
- **Hunter/Scout Bias:** Subtle `+11%` forward directional bias (`0.11 * max(0, dot(u, dir))`) applied only to `SourceCategory.HUNTER_SCOUT`.
- **Smooth Blending:** Polynomial `_smin(a, b, k)` with `k = 135.0` px for preview and `k = 95.0` px for clear core, merging nearby sources smoothly while keeping distant sources separated.

---

## 5. Dirty-Region Algorithm
- On `upsert_source` / `remove_source`, `_mark_source_dirty()` computes the iso-space influence box (`margin_y = max_r * 1.25 + PREVIEW_SD_CLAMP + PREVIEW_SMOOTH_K * 1.5`, `margin_x = margin_y * oval_x`), projects its 4 corners into texel coordinates, clamps to texture bounds, and merges into `_dirty_rect`.
- `apply_incremental_updates()` evaluates `_evaluate_rect(x0, y0, x1, y1)` using active-source AABB culling (with the same `1.5 * k` margin) so distant sources outside the dirty rect are skipped without affecting any byte.

---

## 6. 1× vs 2× Benchmark & Trade-Off Analysis
Observed in `test_terrain_preview_field.gd` on a `128x128` map (and `256x256` max map):

| Metric | 1× (`128x128`) | 2× (`256x256`) |
| --- | --- | --- |
| Memory (`_buffer` + `Image`) | `128 KB` | `512 KB` |
| 1 source full rebuild | `36.45 ms` | `140.79 ms` |
| 3 nearby sources full rebuild | `62.16 ms` | `235.52 ms` |
| 3 nearby sources incremental | `62.72 ms` | `233.21 ms` |
| 8 overlapping sources full rebuild | `121.93 ms` | `478.78 ms` |
| 8 overlapping sources incremental | `120.11 ms` | `488.98 ms` |
| 6 separated sources full rebuild | `103.83 ms` | `376.69 ms` |
| Soldier move incremental | `92.34 ms` | `407.31 ms` |
| Overlapping removal incremental | `86.07 ms` | `318.25 ms` |
| Max map (`256x256`) 1 source full | `57.54 ms` (`512 KB`) | `230.90 ms` (`2048 KB`) |
| Max map (`256x256`) 1 source inc | `32.11 ms` | `122.20 ms` |

**Trade-Off Summary:**
- **CPU Cost:** `2x` (`256x256`) processes `4x` as many texels as `1x` (`128x128`) and takes `140.79 ms` for a 1-source full rebuild and `233–489 ms` for multi-source incremental updates on `128x128` because each source's `~700–890 px` SDF fade + `1.5*k` smooth-min margin spans most of a `128x128` isometric grid.
- **Visual Quality (Expected in M2):** Because `cloud_sea_envelope.gdshader` samples `envelope_tex` with `filter_linear` and evaluates smooth signed-distance fields (`preview_sd` / `core_sd`), `1x` (`128x128`) already interpolates smoothly at both close and wide zoom, whereas `2x` (`256x256`) primarily sharpens the `B` channel (`is_explored`) transitions at close zoom at `4x` CPU/memory cost.
- **Recommendation for M2:** Keep `resolution_scale` configurable (`1` or `2`), test visual quality side-by-side in M2, and coalesce/throttle moving-unit updates (or default to `1x` if `2x` frame spikes exceed budget).

---

## 7. Unit Test, Equivalence & Determinism Evidence
Command:
`& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s "res://scripts/test/test_terrain_preview_field.gd"`
- **Result:** `PASS: test_terrain_preview_field.gd (21 assertions passed, 0 failed)` (`exit=0`).
- **Incremental vs Full Rebuild Equivalence:** Byte-for-byte `Image.get_data()` equality verified at both `1x` (`128x128`) and `2x` (`256x256`) across source registration, soldier movement, overlapping source removal, and Town Hall expansion.
- **Determinism:** Two independent `TerrainPreviewField` instances with identical seed and sources produced byte-for-byte identical `Image.get_data()`.
- **Non-Mutation & Bounds:** Verified `FogOfWar` remained byte-for-byte unchanged and all 4 map corners (`(0,0)`, `(255,0)`, `(0,255)`, `(255,255)`) remained outside preview (`R = 1.0`).

---

## 8. Known Limitations
- **GDScript CPU Cost at 2×:** Because `_evaluate_rect` runs on CPU in GDScript and SDF influence margins (`~700–890 px`) cover large portions of a `128x128` map, frequent per-frame updates of moving soldiers at `2x` (`~233–407 ms`) should be throttled/coalesced in M2 (or run at `1x`).
- **Visual Shader Verification Deferred to M2:** Close-zoom vs wide-zoom visual comparison of `1x` vs `2x` requires `cloud_sea_envelope.gdshader` + `WorldView` integration in M2.

---

## 9. Confirmation of Untouched Production Files
Verified via `git status --short`: no edits were made to `scripts/world/world_view.gd`, `scripts/world/fog_of_war.gd`, `scripts/world/fog_cloud_layer.gd`, `scripts/persistence/save_manager.gd`, existing scenes, existing shaders, or existing cloud assets. Only `scripts/world/terrain_preview_field.gd`, `scripts/test/test_terrain_preview_field.gd`, and this report were created.

**M1 Status:** Complete. Stopping for owner review and authorization before **M2**.
