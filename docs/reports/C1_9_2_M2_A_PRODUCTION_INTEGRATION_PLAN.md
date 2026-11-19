# C1.9.2 — M2-A Production Integration Architecture & Risk Assessment

**Date:** 2026-11-16  
**Milestone:** C1.9.2 — M2-A (Read-Only Architecture Investigation & Staged Integration Plan)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** Read-Only (zero production files modified)

---

## 1. Executive Summary

- **Verdict:** **READY FOR M2-B** (with bounded technical risks documented below).
- **Selected Architecture (Locked):** **Option B — GPU `SubViewport` Envelope Generation** (`1×` default `128×128`, `2×` optional), retaining CPU `TerrainPreviewField` as the authoritative source registry, dirty-state tracker, and headless correctness reference, while keeping `FogOfWar` as the sole authority for exploration, visibility, and entity discovery.
- **Why Production Integration Is Clean:**
  1. All gameplay entity visibility gates in `WorldView` already evaluate `fog_of_war.is_explored()` / `fog_of_war.is_visible()` independently of `TileMapLayer` terrain rendering.
  2. All vision-changing events (`territory_changed`, `unit_moved`, `unit_spawned`, `unit_despawned`, `army_moved`, building changes) already funnel through `WorldView.refresh_world_vision()` (`world_view.gd:4706`).
  3. Both `WorldView._ready()` and `SaveManager` load paths (`rebuild_world_terrain_for_load()` and `_sync_full_fog_and_minimap()`) have deterministic lifecycle hooks for creating, rebinding, and freeing GPU envelope resources.

---

## 2. Actual Baseline & Working-Tree Status

- **Current Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Actual HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c` (matches expected baseline)
- **`git status --short` Count:** `426` entries (all pre-existing 418 modified/untracked files + M0/M1/M1-R1/M1-R2 files/reports preserved untouched)
- **Relevant Existing Files:**
  - `scripts/world/terrain_preview_field.gd` (untracked, M1/M1-R1)
  - `scripts/test/test_terrain_preview_field.gd` (untracked, M1/M1-R1)
  - `scripts/world/fog_cloud_layer.gd` (untracked, legacy cloud overlay)
  - `scripts/world/world_view.gd`, `scripts/world/fog_of_war.gd`, `scripts/persistence/save_manager.gd` (modified pre-existing)
  - `scratch/c1_9_2_m1_r2_gpu_investigation/*` (untracked, M1-R2 prototype)

---

## 3. Production Code Audit (Verified Facts & Line References)

### 3.1 `WorldView` & Scene Hierarchy (`scenes/world/world_view.tscn`, `scripts/world/world_view.gd`)
- **Scene Tree (`world_view.tscn:7-37`):** `WorldView (Node2D)` -> `World (Node2D, y_sort_enabled=true)` -> `TerrainLayer`, `Entities` (`Props`, `Buildings`, `Citizens`), `CursorHighlight (z_index=10)`, `DayNightModulate (CanvasModulate)`.
- **Fog Nodes Mounted Under `World` (`world_view.gd:57-59`, `4276-4376`):**
  - `fog_tile_layer: TileMapLayer` (`z_index = 5`, `position = Vector2(-16, -8)`)
  - `fog_cloud_layer: FogCloudLayer` (`z_index = 7`, `TEXTURE_FILTER_NEAREST`)
  - `cloud_sea_base: Polygon2D` (created by `_create_cloud_sea_base(map_width, map_height, fog_cloud_layer.get_fog_mask_texture())`)
- **`_setup_fog_layer()` (`world_view.gd:4276-4295`):** Frees and nulls any existing `fog_tile_layer`, `cloud_sea_base`, and `fog_cloud_layer` before recreating them.
- **No `_exit_tree()` Override:** `WorldView` currently relies on Godot scene-tree child ownership (`world_root.add_child(...)`) for node cleanup; `RefCounted` managers (`fog_of_war`, `territory_mgr`) are freed automatically when `WorldView` is freed.
- **World Rebuild (`world_view.gd:658-690`, `rebuild_world_terrain_for_load()`):** Regenerates `world_data`, updates `IsoMath.set_active_map_dimensions()`, reinitializes `territory_mgr`, clears/re-renders `terrain_layer`, calls `_setup_fog_layer()`, respawns props, and reinitializes minimap.

### 3.2 `TerrainPreviewField` (`scripts/world/terrain_preview_field.gd`)
- **Verified Public API:** `configure(width, height, seed_value, res_scale=1, fog_of_war=null)`, `register_source(...)`, `upsert_source(...)`, `update_source(...)`, `remove_source(...)`, `clear_sources()`, `has_source()`, `get_source()`, `get_source_ids()`, `get_source_count()`, `has_pending_dirty_rect()`, `rebuild_full()`, `apply_incremental_updates()`, `get_envelope_image()`, `get_envelope_texture()`.
- **API Gap Identified for M2-B:** `TerrainPreviewField` currently stores `_phase_a` and `_phase_b` as private fields and does not expose a dedicated `get_gpu_source_snapshot()` / `get_phase_offsets() -> Vector2` helper. Adding a small public getter (`get_phase_offsets()`, `pack_sources_for_gpu()`) in M2-B avoids accessing private `_phase_a`/`_phase_b` from `WorldView`.
- **Coordinate Consistency:** `TerrainPreviewField` and `envelope_gen.gdshader` both map `uv_grid = UV * map_size - 0.5` to `p_iso = ((u - v) * 16.0, (u + v) * 8.0)`, verified in M1-R2 to match within `1/255` LSB at `2×` (`max_R=1/255, max_G=1/255`).

### 3.3 `FogOfWar` & Entity Visibility (`scripts/world/fog_of_war.gd`, `scripts/world/world_view.gd`)
- **States (`fog_of_war.gd`):** `State.UNEXPLORED = 0`, `State.EXPLORED = 1`, `State.VISIBLE = 2`.
- **Verified Production Visibility Gates (`world_view.gd`):**
  - Props/resources (`prop_nodes_by_cell`): gated by `fog_of_war.is_explored(cell)`.
  - POIs (`refresh_poi_visibility()`, `lines 978-1010`): gated by `poi.state != POIManager.POIState.UNDISCOVERED` (discovered in `refresh_world_vision()` when `fog_of_war.is_visible(...)`).
  - Wildlife (`wildlife_mgr.refresh_visibility(fog_of_war, debug_fog_disabled)`, `line 4702`) & Monsters (`monster_mgr.refresh_visibility(...)`, `line 4704`).
  - Enemy military (`enemy_military_mgr`) & Siege objectives (`field_siege_mgr`): gated by `fog_of_war` in `_refresh_dynamic_actor_visibility()`.
- **Legacy Test Contracts:** `test_fog_rendering.gd`, `test_fog_cloud_overlay.gd`, `test_fog_debug_toggle.gd`, `test_hybrid_boundary_visuals.gd`, and `test_fast_fog_mask_extended.gd` assert `fog_tile_layer` and `FogCloudLayer` methods/visibility.

### 3.4 `SaveManager` (`scripts/persistence/save_manager.gd`)
- **Save (`lines 396-406`):** Serializes `data["fog_of_war"]` as `[x, y]` pairs where `state != UNEXPLORED`.
- **Load Order (`lines 2110-2124`, `2822-2843`, `2961-2967`):**
  1. Rebuilds `world_data` / `nav` (or calls `rebuild_world_terrain_for_load()` which calls `_setup_fog_layer()`).
  2. Checks `loaded_fow`: if `null` or dimensions mismatch, assigns a **new** `FogOfWar.new(target_width, target_height)` (`line 2124`)!
  3. Deserializes buildings, citizens, tactical units, player army, wildlife, monsters.
  4. Resets `fow` and restores `EXPLORED` cells (`lines 2832-2838`).
  5. Calls `world_view.call("refresh_world_vision")` (`line 2963`), `world_view.call("_sync_full_fog_and_minimap")` (`line 2965`), and `refresh_poi_visibility()` (`line 2967`).

### 3.5 Day/Night Integration (`world_view.gd:4849-4860`, `fog_cloud_layer.gd:430-455`)
- `WorldView.sync_day_night_visuals()` sets `World/DayNightModulate.color = get_ambient_color_for_time(cont_h)` and calls `fog_cloud_layer.apply_day_night_tint(cont_h)`.
- **Important Rendering Finding:** `World/DayNightModulate` (`CanvasModulate`) is a sibling of `cloud_sea_base` inside `World`, so `CanvasModulate` **already multiplies** `cloud_sea_base` unless `cloud_sea_base` uses a separate tint or `CanvasItemMaterial` `light_mode`. In M2-C, the cloud composite shader should receive `day_night_tint` only via one authoritative path (matching `FogCloudLayer`'s `day_tint`/`dawn_tint`/`dusk_tint`/`night_tint` without double-multiplying `DayNightModulate`).

### 3.6 Gameplay Preview Sources (`world_view.gd`, `citizen_controller.gd`, `tactical_military_manager.gd`, `player_army_manager.gd`)
- **Town Hall + Territory Expansion:**
  - Owner: `world_data.center_spawn` + `BuildingSystem.is_town_hall_active(world_data)` + `territory_mgr` (`signal territory_changed(new_level, owned_count, revision)` -> `_on_territory_changed()`).
  - Stable ID: `"town_hall"`.
  - Radius scaling: base `310.0` / `165.0` px scaled smoothly with `territory_mgr` level/radius so territory expansion grows the single `"town_hall"` preview region.
- **Hunter / Scout:**
  - Owner: `WorldView.citizen_list` (`CitizenController`).
  - **Audit Finding:** `world_view.gd:4725` checks `cit.get("can_scout_beyond_territory") == true`, while `CitizenController` (`citizen_controller.gd:43, 216`) uses `role == "hunter"`, `citizen_id`, `current_cell`, `facing_dir`, and `signal citizen_died(citizen_id)`.
  - Stable ID: `"hunter:" + cit.citizen_id` (fallback `str(cit.get_instance_id())`).
  - Direction: derived from `cit.facing_dir` (`ContinuousPathFollower.ScreenDir`) mapped to a normalized 2D screen vector.
  - Removal: when `not is_instance_valid(cit)`, `citizen_died`, or `role != "hunter" and not can_scout_beyond_territory`.
- **Soldiers / Army:**
  - Owner: `tactical_military_mgr` (`get_all_units()`, signals `unit_spawned`, `unit_moved`, `unit_despawned`) and fallback `player_army_mgr` (`army_moved`, `soldier_count > 0`, `current_cell`).
  - Stable ID: `"soldier:" + u.unit_id` (or `"army:main"` when abstract army fallback is active).
  - Movement & Removal: `update_source` replaces `cell` in place (zero historical trail); removed when `not u.is_alive` or `unit_despawned`.

---

## 4. Proposed GPU `SubViewport` Architecture (Option B)

### 4.1 Ownership & Lifecycle
- **Owner:** A dedicated lightweight helper node or `WorldView`-owned controller (recommended: `TerrainPreviewRenderer` child node or encapsulated helper owned by `WorldView`, freed and recreated cleanly inside `_setup_fog_layer()`).
- **Node Setup:**
  - `SubViewport` (`disable_3d = true`, `transparent_bg = false`, `render_target_update_mode = SubViewport.UPDATE_DISABLED`, `size = Vector2i(map_w * res_scale, map_h * res_scale)`).
  - Child `ColorRect` (`PRESET_FULL_RECT`, `ShaderMaterial` using `shaders/fog/terrain_preview_envelope.gdshader`).
  - `envelope_gen.gdshader` remains completely **Day/Night neutral** (outputs pure `R = preview_sd`, `G = core_sd`).
- **Coalesced Update Scheduling:**
  - Source mutations (`register`/`upsert`/`update`/`remove`) update `TerrainPreviewField` (CPU registry) and set a `_preview_dirty = true` flag.
  - Once per frame (in `_process()` or at the end of `refresh_world_vision()` via `call_deferred("_flush_terrain_preview")`), if `_preview_dirty` is true:
    1. Pack active sources and upload to the GPU shader.
    2. Set `sub_vp.render_target_update_mode = SubViewport.UPDATE_ONCE`.
    3. Clear `_preview_dirty = false` (Godot automatically resets `UPDATE_ONCE` -> `UPDATE_DISABLED` after rendering that frame).
  - **Initial Frame:** During `_setup_fog_layer()`, trigger `UPDATE_ONCE` immediately after registering initial sources so frame 1 has a valid envelope.

### 4.2 Source Capacity Recommendation
- **Finding:** M1-R2's `MAX_SOURCES = 32` uniform array can be exceeded in late-game or stress tests if a player fields 25+ tactical soldiers + multiple hunters + Town Hall.
- **Recommendation:** **Option 3 — GPU `RGBAF` Data Texture (`source_data_tex`)** (e.g., `128 × 2` `Image.FORMAT_RGBAF`, `FILTER_NEAREST`, `8 KB` RAM/VRAM):
  - Row 0 (`y = 0`): `(center_iso.x, center_iso.y, preview_radius_px, core_radius_px)`
  - Row 1 (`y = 1`): `(dir.x, dir.y, oval_x, has_dir)`
  - `envelope_gen.gdshader` reads `texelFetch(source_data_tex, ivec2(i, 0), 0)` and `texelFetch(source_data_tex, ivec2(i, 1), 0)` up to `source_count` (hard-capped at `128` with explicit `push_warning` + deterministic priority sorting if ever exceeded — never silent discard).

### 4.3 Separate `FogOfWar` Texture
- Maintain a dedicated `128×128` (or `map_w × map_h`) `Image` (`FORMAT_R8`, `16 KB`) + `ImageTexture` (`fow_explored_tex`, `filter_nearest`), storing `255` where `fog_of_war.is_explored(cell)` else `0`.
- Updated incrementally on `_update_fog_visuals(dirty_cells)` and fully on `_sync_full_fog_layer()` (after any `SaveManager` `fog_of_war` replacement!).

### 4.4 Legacy Transition & `debug_fog_disabled`
- Preserve `fog_tile_layer` and `FogCloudLayer` APIs and nodes so existing unit tests (`test_fog_rendering.gd`, `test_fog_cloud_overlay.gd`, `test_hybrid_boundary_visuals.gd`, `test_fast_fog_mask_extended.gd`) continue passing.
- In M2-C, when the new C1.9.2 `cloud_sea_base` envelope shader is active in `WorldView`:
  - `fog_tile_layer.visible = false` and `fog_cloud_layer.visible = false` (or `fog_cloud_layer` sprite chunks suppressed) so legacy dark tiles/sprites do NOT render over terrain-previewed `UNEXPLORED` cells and do not duplicate fog rendering.
  - `set_debug_fog_disabled(disabled)` hides `cloud_sea_base` when `disabled == true` without mutating `FogOfWar` or `TerrainPreviewField`.

---

## 5. Staged M2 Implementation Plan (M2-B through M2-E)

| Milestone | Scope | Files Expected to Change / Create | Acceptance Criteria |
| --- | --- | --- | --- |
| **M2-B** | `TerrainPreviewField` GPU packing API + `SubViewport` envelope resource & lifecycle | **Modify:** `scripts/world/terrain_preview_field.gd`<br>**Create:** `shaders/fog/terrain_preview_envelope.gdshader`, `scripts/world/terrain_preview_renderer.gd`, `scripts/test/test_terrain_preview_gpu_equiv.gd` | `SubViewport` initializes cleanly, coalesces updates (`UPDATE_ONCE` -> `UPDATE_DISABLED`), matches CPU `TerrainPreviewField` within `<= 2/255` tolerance (`2×`) / `<= 4/255` (`1×`), zero leaks on rebuild/free. |
| **M2-C** | Cloud composite shader promotion + `WorldView` visual mounting + Day/Night + `debug_fog_disabled` | **Promote Assets:** `assets/fog/cloud_wisps_sea_1024.png`, `assets/fog/cloud_banks_macro_1024.png`<br>**Create:** `shaders/fog/cloud_sea_envelope.gdshader`<br>**Modify:** `scripts/world/world_view.gd` | Approved C1.9.1 cloud sea renders with `TEXTURE_FILTER_LINEAR`, single Day/Night tint (no double-tinting), legacy `fog_tile_layer` hidden in gameplay without breaking `test_fog_debug_toggle.gd`. |
| **M2-D** | Gameplay source registration & coalesced updates (Town Hall, Territory, Hunter/Scout, Soldiers) | **Modify:** `scripts/world/world_view.gd`<br>**Create:** `scripts/test/test_terrain_preview_sources.gd` | Town Hall expands smoothly on `territory_changed`, Hunter shows subtle directional bias, Soldiers show local preview with zero historical trails, removals preserve overlapping sources. |
| **M2-E** | Save/Load rebinding + Full Regression & Performance Verification | **Verify/Modify (if needed):** `scripts/world/world_view.gd`, `scripts/persistence/save_manager.gd`<br>**Create:** `scripts/test/test_c1_9_2_integration.gd` | Save/Load reconstructs `TerrainPreviewField`, `SubViewport`, and `fow_explored_tex` cleanly; entities in preview-only `UNEXPLORED` terrain remain hidden; all regression suites pass. |

---

## 6. Performance Budget & Validation Methodology

- **M2 Performance Budget (Target on `1280×720` Forward+ D3D12):**
  - Main-thread CPU source sync + data texture pack: **`< 0.5 ms`** per changed tick (`0.00 ms` idle).
  - `SubViewport` GPU pass (`1×` `128×128`): **`< 0.2 ms`** on changed tick (`0.00 ms` idle).
  - Cloud composite GPU pass: **`< 1.0 ms`** per frame.
  - Note: M1-R2 timings (`0.05–0.09 ms` CPU, `0.011–0.026 ms` SubViewport GPU) were measured on an RTX 3050 Ti; integrated GPUs will be slower, so keeping `1×` (`128×128`) as default and coalescing updates to once per tick is essential.

---

## 7. Regression Test Matrix

| Area | Verification Target |
| --- | --- |
| `FogOfWar` | `UNEXPLORED` / `EXPLORED` / `VISIBLE` semantics & save schema unchanged |
| Entity / Prop / POI / Wildlife / Monster / Enemy | Hidden in preview-only `UNEXPLORED` terrain until `FogOfWar` discovers them |
| Town Hall & Territory | Initial preview + smooth expansion on `territory_changed` |
| Hunter / Scout | Subtle directional preview + removal on death/role change |
| Soldiers | Current-position local preview, zero historical trails, clean despawn |
| Multi-Source | Merge, separation, update, overlapping removal, >32 source capacity |
| Save / Load | Clean `fog_of_war` rebinding, `rebuild_world_terrain_for_load()`, no stale `ViewportTexture` |
| Day / Night | Single ambient tint, no double-tinting with `DayNightModulate` |
| GPU Lifecycle | `UPDATE_ONCE` -> `UPDATE_DISABLED`, no duplicate `SubViewport`, clean teardown |
| Legacy Suites | `test_fog_of_war_reconnaissance.gd`, `test_fog_rendering.gd`, `test_fog_cloud_overlay.gd`, `test_fog_debug_toggle.gd`, `test_hybrid_boundary_visuals.gd`, `test_fast_fog_mask_extended.gd`, `test_save_load.gd` |

---

## 8. Key Risks & Mitigations

1. **`test_fog_rendering.gd` & `test_hybrid_boundary_visuals.gd` Expect `fog_tile_layer` State:** Keeping `fog_tile_layer` populated underneath while setting `fog_tile_layer.visible = false` (or toggling via a flag) preserves all tile-state assertions without visual duplication; however, `test_fog_debug_toggle.gd:33` asserts `wv.fog_tile_layer.visible` is `true` by default — this test expectation will need an explicit M2-C/M2-E update if `fog_tile_layer` is hidden in favor of `cloud_sea_base`.
2. **Double Day/Night Tinting:** `DayNightModulate` (`CanvasModulate`) affects `World` children. If `cloud_sea_base` is a child of `World`, applying `apply_day_night_tint()` inside the shader *as well* as `CanvasModulate` would double-tint the clouds. M2-C must verify whether `cloud_sea_base` uses `CanvasModulate` alone or `unshaded`/separate `CanvasLayer` with shader tint.
3. **`SaveManager` Replacing `fog_of_war` Instance (`save_manager.gd:2124`):** Rebinding `TerrainPreviewField` and `fow_explored_tex` inside `_setup_fog_layer()` and `_sync_full_fog_and_minimap()` guarantees no stale `FogOfWar` reference survives load.

---

## 9. Confirmation of Read-Only Compliance

- **No production files were modified.**
- **No existing files were overwritten.**
- **No changes were staged, committed, or pushed.**
- **All 426 working-tree entries remain preserved.**
