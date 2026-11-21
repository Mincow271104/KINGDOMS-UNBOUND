# KINGDOMS UNBOUND — C1.6.2 Implementation Report
## CloudSeaBase V5 MultiScale Production Integration

**Engine:** Godot 4.7 (`4.7-stable`, Windows)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Baseline HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Milestone:** C1.6.2 — `CloudSeaBase` V5 MultiScale Production Integration

---

## 1. Pre-Implementation Git State

Recorded in `scratch/c1_6_2_baseline_git.txt` prior to edits:
- **HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Working Tree:** `411` pre-existing modified/untracked entries preserved untouched. No `git reset`, `git clean`, `git stash`, staging, commit, or push was performed.

---

## 2. Exact Files Added and Modified

### Modified
- `scripts/world/world_view.gd` — Added `cloud_sea_base: Polygon2D`, cached static `_cloud_sea_shader`, `_get_cloud_sea_shader()`, `_create_cloud_sea_base()`, `CloudSeaBase` lifecycle management in `_setup_fog_layer()` (using `remove_child()` + `queue_free()` to prevent duplicate nodes), `fog_mask` rebinding in `_sync_full_fog_layer()`, and visibility synchronization in `_sync_full_fog_and_minimap()`, `set_debug_fog_disabled()`, and `set_cloud_overlay_enabled()`.
- `scripts/world/fog_cloud_layer.gd` — Updated `z_index` from `6` to `7` so `FogCloudLayer` renders above `CloudSeaBase` (`z = 6`) and below `CursorHighlight` (`z = 10`).
- `scripts/test/test_fog_cloud_overlay.gd` — Expanded with `CloudSeaBase` type/existence, `z = 5/6/7/10` + `HUD` hierarchy, V5 texture/shader parameter assertions, `fog_mask` connection, initial & incremental mask sync, overlay toggle, and repeated `_setup_fog_layer()` non-duplication checks (`47` assertions).

### Added / Imported
- `assets/fog/*.png.import` (generated via `Godot --headless --import --quit` for the 5 C1.6.1 promoted PNG assets so `load("res://assets/fog/...")` resolves cleanly in headless and runtime builds).
- `docs/reports/CLOUD_SEA_C1_6_2_IMPLEMENTATION_REPORT.md`

---

## 3. CloudSeaBase Node and Shader Architecture

- **Node:** `CloudSeaBase` (`Polygon2D`), child of `WorldView/World` (`z_index = 6`, `texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST`).
- **Geometry:** Isometric diamond quad computed from `FogOfWar.map_width` (`mw`) and `FogOfWar.map_height` (`mh`) at continuous cell corners `(-0.5, -0.5)` to `(mw - 0.5, mh - 0.5)` via `IsoMath.HALF_WIDTH` / `IsoMath.HALF_HEIGHT`.
- **Shader Reuse:** Uses the exact C1.5.5 V5 MultiScale `canvas_item` shader cached in `WorldView._cloud_sea_shader` (zero per-frame shader or texture reallocation).
- **World-Space UV & Camera Invariance:** `v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy` maps world-space coordinates directly, ensuring `Camera2D` pan/zoom produces zero UV swimming.

---

## 4. Shader Parameters and Texture Connections

| Parameter | Value / Binding | Notes |
| :--- | :--- | :--- |
| `base_tex` | `res://assets/fog/cloud_sea_base_v4_512.png` | `512×512` horizontal cloud strata (`repeat_enable, filter_nearest`) |
| `wisp_tex` | `res://assets/fog/cloud_sea_base_v5_wisps_512.png` | `512×512` secondary `#1C2A46` wisps (`repeat_enable, filter_nearest`) |
| `fog_mask` | `FogCloudLayer.get_fog_mask_texture()` | `FORMAT_RGBA8` `ImageTexture` (`repeat_disable, filter_linear`) |
| `map_size` | `Vector2(float(mw), float(mh))` | Dynamically matches `FogOfWar` dimensions |
| `tex_scale` | `512.0` | Base strata world-pixel period |
| `wisp_scale` | `640.0` | Secondary wisp world-pixel period (`+ vec2(0.37, 0.19)` offset, `mix(..., wcol.a * 0.85)`) |
| `use_wisp` | `1.0` | Enables V5 multi-scale wisp blending |
| `base_alpha` | `0.96` | Base layer alpha |

---

## 5. Fog Mask Synchronization Mechanism

- `FogCloudLayer` remains the single owner of `_fog_mask_img` and `_fog_mask_tex` (no duplicate mask cache).
- **Initial Sync:** `_setup_fog_layer()` calls `fog_cloud_layer.configure(...)` -> `sync_full()` -> `_sync_full_fog_mask_fast()` + `_upload_fog_mask()`, then binds `fog_cloud_layer.get_fog_mask_texture()` to `CloudSeaBase`.
- **Incremental Updates:** `WorldView._update_fog_visuals(dirty_cells)` calls `fog_cloud_layer.update_dirty_cells(dirty_cells)`, which updates `_fog_mask_img` via `_sync_dirty_fog_mask_fast()` and uploads in-place via `_fog_mask_tex.update(_fog_mask_img)`.
- **Full Sync:** `_sync_full_fog_layer()` also re-applies `fog_cloud_layer.get_fog_mask_texture()` to `CloudSeaBase`'s `ShaderMaterial` in case `ImageTexture` was recreated.

---

## 6. Final Z-Index Hierarchy

Verified by `test_fog_cloud_overlay.gd`:
1. `FogTileMapLayer` (A2): `z_index = 5`
2. `CloudSeaBase` (`Polygon2D`): `z_index = 6`
3. `FogCloudLayer` (`Node2D`): `z_index = 7`
4. `CursorHighlight` (`Sprite2D`): `z_index = 10`
5. `HUD`: sibling `CanvasLayer` (unchanged, unaffected)

---

## 7. Test Results

| Suite | Assertions / Result | Exit Code | Notes |
| :--- | :--- | :---: | :--- |
| `scripts/test/test_fog_cloud_overlay.gd` | **PASS (`47` passed, `0` failed)** | **`0`** | Baseline exit warnings (`21 ObjectDB`, `8 resources`). |
| `scripts/test/test_fast_fog_mask_extended.gd` | **PASS (`78` passed, `0` failed)** | **`0`** | Zero leaks/warnings (`64×64`, `128×128`, `256×256`). |
| `scripts/test/test_fog_rendering.gd` | **PASS (`24` passed, `0` failed)** | **`0`** | Baseline exit warnings (`33 ObjectDB`, `8 resources`). |
| `scripts/test/test_fog_debug_toggle.gd` | **PASS (`15` passed, `0` failed)** | **`0`** | Baseline exit warnings (`21 ObjectDB`, `8 resources`). |

---

## 8. Visual Verification Screenshots

Captured from live `WorldView` (`128×128`, `1.5×` zoom, `12:00` Day, D3D12 Forward+) in `scratch/c1_6_2_screenshots/`:
- `c1_6_2_settlement_day.png` — Confirmed `CloudSeaBase` (`z=6`) renders beneath legacy foreground clouds (`z=7`), cleanly frames the settlement via A2 + Bayer-dithered `fog_mask`, and leaves `HUD` unaffected.
- `c1_6_2_deep_cloud_sea_day.png` — Confirmed continuous V5 horizontal cloud-band background across deep unexplored territory with zero seams.
- `c1_6_2_after_reveal_day.png` — Confirmed incremental scout reveal clears `CloudSeaBase`, `FogCloudLayer`, and `FogTileMapLayer` together with zero stale cloud coverage.

---

## 9. Known Warnings and Limitations

- Existing `WorldView` test suites emit pre-existing Godot exit warnings (`21–33 ObjectDB instances leaked`, `8 resources still in use`) unrelated to C1.6.2.
- Foreground clouds still use the legacy `48×48` sprites (`C1.6.3` scope), and `apply_day_night_tint()` still applies legacy RGB tinting (`C1.6.4` scope).

---

## 10. Scope Compliance

Strictly adhered to C1.6.2 restrictions:
- Foreground Main Cloud sprites (`main_cloud_01..03.png`) and density presets were NOT integrated.
- `apply_day_night_tint()` and `DayNightModulate` were NOT modified.
- `scripts/persistence/save_manager.gd`, save schema, and Save/Load dimension mismatch rebinding were NOT modified.
- No gameplay, citizen, military, or economy systems were modified.

---

## 11. Remaining Work for C1.6.3

- Switch `FogCloudLayer` foreground placement to Version A (`main_cloud_01..03.png`) at `A_Medium` density (and update `test_fog_cloud_overlay.gd` texture size expectations accordingly).
- Subsequent milestones: C1.6.4 (Day/Night single-authority tint fix) and C1.6.5 (Save/Load cross-dimension `FogOfWar` rebind guard + full regression).
