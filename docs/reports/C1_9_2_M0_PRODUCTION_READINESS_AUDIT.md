# C1.9.2 — M0 Production Readiness Audit (Read-Only)

**Date:** 2026-11-16  
**Milestone:** C1.9.2 — M0 Production Readiness Audit  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Pre-existing Working Tree Status:** `418` `git status --short` entries preserved untouched  
**Mode:** Read-only audit (no production code, scenes, or assets modified)

---

## 1. Executive Summary

The C1.9.1 baseline (`Approach C — Hybrid Preview Regions + Cloud-Shaped Visual Envelope`) can be integrated cleanly into production without changing `FogOfWar` gameplay semantics, `SaveManager` persistence format, or entity visibility rules.

Key architectural findings:
1. **`FogOfWar` & Entity Decoupling Already Exists:** All gameplay entity visibility gates (`prop_nodes_by_cell`, `poi_mgr`, `enemy_military_mgr`, `field_siege_mgr`, `wildlife_mgr`, `monster_mgr`) already evaluate `fog_of_war.is_explored()` / `fog_of_war.is_visible()` in GDScript, independent of `TileMapLayer` terrain rendering.
2. **Legacy Cloud/Tile Overlap Must Be Carefully Handled:** Currently `WorldView` mounts `fog_tile_layer` (`TileMapLayer`), `cloud_sea_base` (`Polygon2D`), and `fog_cloud_layer` (`FogCloudLayer` with `z_index = 7` and `TEXTURE_FILTER_NEAREST`). Existing regression tests (`test_fog_rendering.gd`, `test_fog_cloud_overlay.gd`, `test_fog_debug_toggle.gd`, `test_hybrid_boundary_visuals.gd`, `test_fast_fog_mask_extended.gd`) assert internal and public contracts on these nodes.
3. **Shader & Filtering Requirements:** `project.godot` configures `default_texture_filter=0` (Nearest) and `snap_2d_transforms_to_pixel=true`. The C1.9.1 cloud sea `Polygon2D` and shader samplers must explicitly use `TEXTURE_FILTER_LINEAR` and `filter_linear` so cloud envelopes and textures do not pixel-snap. Also, Godot 4.7 `canvas_item` shaders forbid `return;` inside `fragment()`, requiring `if / else` blocks (already respected in `c1_9_1_envelope_cloud.gdshader`).
4. **Asset Promotion Required in M2:** `cloud_wisps_sea_1024.png` and `cloud_banks_macro_1024.png` currently reside in `scratch/c1_8_cloud_reference_redesign/assets/` and must be promoted to `assets/fog/` during M2.

---

## 2. Current Production Architecture Trace

### 2.1 Authoritative Gameplay Fog (`scripts/world/fog_of_war.gd`)
- **States:** `State.UNEXPLORED = 0`, `State.EXPLORED = 1`, `State.VISIBLE = 2`.
- **Vision Radii:**
  - `TOWN_HALL_VISION_RADIUS = 10`
  - `WATCHTOWER_VISION_RADIUS = 15`
  - `OUTPOST_VISION_RADIUS = 6`
  - `ARMY_UNIT_VISION_RADIUS = 4`
  - `CITIZEN_VISION_RADIUS = 4`
- **Core Methods:** `reveal_circle()`, `recompute_vision()`, `rebuild_visible_cache()`.
- **Coordinate System (`scripts/utils/iso_math.gd`):** `TILE_WIDTH = 32.0`, `TILE_HEIGHT = 16.0`, `HALF_WIDTH = 16.0`, `HALF_HEIGHT = 8.0`, `map_to_local()`, `local_to_map()`.

### 2.2 Territory & Vision Signals (`scripts/world/territory_manager.gd`, `scripts/world/world_view.gd`)
- `TerritoryManager` emits `territory_changed(new_level, owned_count, revision)` from `recalculate_territory()`.
- `WorldView` initializes `fog_of_war = FogOfWar.new(...)` and calls `fog_of_war.reveal_circle(world_data.center_spawn, 10)` (`world_view.gd:365-395`).
- `WorldView` connects `territory_mgr.territory_changed` to `_on_territory_changed()` and updates vision via `refresh_world_vision()`, `_on_tactical_unit_moved/spawned/despawned()`, and `_on_player_army_moved()`.
- Specialized citizen scouting (`world_view.gd:4725`) checks `cit.get("can_scout_beyond_territory") == true` (while Hunters also respect `wildlife_mgr.is_cell_permitted_for_hunter()`).
- POI visibility (`world_view.gd:978-1010`, `refresh_poi_visibility()`) checks `poi.state != POIManager.POIState.UNDISCOVERED`.

### 2.3 Current Visual Fog & Cloud Stack (`scripts/world/world_view.gd`, `scripts/world/fog_cloud_layer.gd`)
- `WorldView` fields (`world_view.gd:57-62`):
  - `fog_tile_layer: TileMapLayer`
  - `cloud_sea_base: Polygon2D`
  - `fog_cloud_layer: FogCloudLayer`
  - `CLOUD_SEA_BASE_TEX_PATH = "res://assets/fog/cloud_sea_base_v4_512.png"`
  - `CLOUD_SEA_WISP_TEX_PATH = "res://assets/fog/cloud_sea_base_v5_wisps_512.png"`
- Setup & Sync (`world_view.gd:4276-4580`, `4670-4875`):
  - `_setup_fog_layer()` instantiates `fog_cloud_layer = FogCloudLayer.new()`, calls `fog_cloud_layer.configure(fog_of_war, cloud_seed, FogCloudLayer.DensityPreset.BALANCED)`, and creates `cloud_sea_base = _create_cloud_sea_base(fog_of_war.map_width, fog_of_war.map_height, fog_cloud_layer.get_fog_mask_texture())`.
  - `_sync_fog_cell()`, `_sync_full_fog_layer()`, `_sync_full_fog_and_minimap()`, and `_update_fog_visuals()` update `fog_tile_layer` and call `fog_cloud_layer.update_dirty_cells(dirty_cells)`.
  - `sync_day_night_visuals()` (`world_view.gd:4849-4860`) sets `DayNightModulate.color = get_ambient_color_for_time(cont_h)` and calls `fog_cloud_layer.apply_day_night_tint(cont_h)`.
  - `FogCloudLayer.apply_day_night_tint(continuous_hour)` interpolates `day_tint`, `dawn_tint`, `dusk_tint`, and `night_tint`.
  - Debug controls: `set_debug_fog_disabled()`, `is_debug_fog_disabled()`, `set_cloud_overlay_enabled()`, `set_cloud_density_preset()`.

### 2.4 Save/Load Persistence (`scripts/persistence/save_manager.gd`)
- **Save (`lines 396-406`):** Serializes `data["fog_of_war"]` as an `Array` of `[x, y]` pairs where `state != UNEXPLORED`.
- **Validate (`lines 1880-1888`):** Validates `fog_of_war` payload structure.
- **Load (`lines 2122-2124`, `2822-2840`, `2961-2965`):** Recreates/resets `fog_of_war`, restores saved cells to `FogOfWar.State.EXPLORED`, and invokes `world_view.call("_sync_full_fog_and_minimap")`.

---

## 3. Baseline Test Results (Observed in M0)

Executed via `"E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s "res://scripts/test/<script>"`:

| Test Script | Exit Code | Notes |
| --- | --- | --- |
| `test_fog_of_war_reconnaissance.gd` | `0` | Passed |
| `test_fog_rendering.gd` | `0` | Passed (asserts `fog_tile_layer` 32x16 atlas & `alt=0/1`) |
| `test_fog_cloud_overlay.gd` | `0` | Passed (asserts `FogCloudLayer` Version A textures, `TEXTURE_FILTER_NEAREST`, `_chunk_nodes`, `_layout_cache`, `_is_opaque_footprint_unexplored`) |
| `test_fog_debug_toggle.gd` | `0` | Passed (asserts `set_debug_fog_disabled`, `fog_tile_layer.visible`, `minimap.debug_fog_disabled`, `FogOfWar` grid invariance) |
| `test_hybrid_boundary_visuals.gd` | `0` | Passed (asserts `fog_tile_layer` 16-mask atlas & incremental vs full sync equivalence) |
| `test_fast_fog_mask_extended.gd` | `0` | Passed (asserts `FogCloudLayer._sync_full_fog_mask_ref()` vs `_sync_full_fog_mask_fast()`) |
| `test_save_load.gd` | `0` | Passed |

---

## 4. Target C1.9.2 Integration Plan (M1–M3)

### 4.1 Exact Files to Create / Modify
- **M1 (Domain Model — `TerrainPreviewField`):**
  - **Create:** `scripts/world/terrain_preview_field.gd` — pure data/SDF envelope evaluator (`_smin`, `_eval_source_sd`, source registry, `envelope_tex` `Image` + `ImageTexture` generation and dirty-rect updates, deterministic seed-based macro lobe parameters).
  - **Create:** `scripts/test/test_terrain_preview_field.gd` — unit tests for source lifecycle, smooth-min blending, dirty-rect vs full rebuild equivalence, determinism, and zero `FogOfWar` mutation.
- **M2 (Visual Integration — Cloud Sea Envelope Shader & `WorldView`):**
  - **Promote Assets:** Copy `cloud_wisps_sea_1024.png` and `cloud_banks_macro_1024.png` from `scratch/c1_8_cloud_reference_redesign/assets/` to `assets/fog/`.
  - **Create Shader:** `shaders/fog/cloud_sea_envelope.gdshader` (promoted from `scratch/c1_9_1_shape_correction/shaders/c1_9_1_envelope_cloud.gdshader`, adding day/night tint uniform support matching `FogCloudLayer.apply_day_night_tint()`).
  - **Modify:** `scripts/world/world_view.gd` — instantiate `TerrainPreviewField`, rebuild/update preview sources from Town Hall, Outposts, Watchtowers, explored territory/units/scouts, and connect `cloud_sea_base` to `cloud_sea_envelope.gdshader` + `envelope_tex` with `TEXTURE_FILTER_LINEAR`. Preserve `FogOfWar` gameplay gating and `sync_day_night_visuals()` tinting.
- **M3 (Hardening, Save/Load & Regression Verification):**
  - **Verify/Update (if needed):** `scripts/persistence/save_manager.gd` integration via `_sync_full_fog_and_minimap()` so loaded games reconstruct `TerrainPreviewField` deterministically from restored `FogOfWar` + buildings/territory without changing the save schema.
  - **Create/Update Tests:** Integration tests covering `WorldView` preview envelope sync, debug fog toggle (`set_debug_fog_disabled`), day/night cloud tinting, entity concealment inside preview-only terrain (`UNEXPLORED` entities stay hidden), and save/load roundtrip.

### 4.2 Proposed `TerrainPreviewField` API & Ownership
- **Class:** `TerrainPreviewField` (extends `RefCounted`, `class_name TerrainPreviewField`)
- **Inputs / State:**
  - `map_width: int`, `map_height: int`, `world_seed: int`
  - Preview sources keyed by stable ID (e.g. `"town_hall"`, `"outpost:<id>"`, `"watchtower:<id>"`, `"territory"`, `"unit:<id>"`, `"explored_patch:<id>"`), storing `{center: Vector2, radius: float, aspect: float, angle: float, seed_offset: float}`.
  - `envelope_image: Image` (`FORMAT_RF` or `FORMAT_RGBA8` matching shader expectations) and `envelope_texture: ImageTexture`.
- **Core Methods:**
  - `configure(width: int, height: int, seed: int) -> void`
  - `set_sources(sources: Array[Dictionary]) -> void` / `upsert_source(id: String, params: Dictionary) -> void` / `remove_source(id: String) -> void`
  - `rebuild_full() -> void`
  - `update_dirty_rect(dirty_cell_rect: Rect2i) -> void`
  - `get_envelope_texture() -> ImageTexture`
  - `is_terrain_previewed(cell: Vector2i) -> bool` (diagnostic/test helper only — never used for gameplay entity visibility)
- **Ownership:** `WorldView` owns the `TerrainPreviewField` instance and its `ImageTexture`. `FogOfWar` has zero dependency on `TerrainPreviewField`.

### 4.3 Source Lifecycle, Incremental Updates & Save/Load Strategy
- **Source Lifecycle:**
  - Startup / `WorldView._ready()`: register Town Hall anchor and initial explored/territory envelope.
  - Dynamic events: `territory_changed`, building placed/destroyed (Outposts, Watchtowers), tactical unit / army / scouting citizen movement.
- **Incremental Update Strategy:**
  - Maintain dirty world/cell bounding rect expanded by `max_source_radius + smooth_k + margin` when sources are added/moved/removed, updating only affected texels in `envelope_image` and calling `envelope_texture.update(envelope_image)`.
  - Fall back to `rebuild_full()` on initial setup, `configure()`, or save/load restoration.
- **Save/Load Reconstruction Strategy:**
  - **Zero save-schema breaking changes:** `SaveManager` continues saving/loading `data["fog_of_war"]` (`EXPLORED` cells) and building/territory/unit state.
  - On load, `SaveManager` calls `world_view.call("_sync_full_fog_and_minimap")`, which will also trigger `TerrainPreviewField` source reconstruction from restored structures, territory, and `FogOfWar` explored clusters + `rebuild_full()`.

### 4.4 Day/Night & Shader Resource Lifecycle
- `cloud_sea_envelope.gdshader` will expose a `vec4 cloud_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);` uniform (or equivalent) driven by `WorldView.sync_day_night_visuals()` using the same `day_tint` / `dawn_tint` / `dusk_tint` / `night_tint` curve as `FogCloudLayer`.
- `cloud_sea_base` (`Polygon2D`) must explicitly set `texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR` to override `project.godot`'s `default_texture_filter=0` (Nearest).
- Shader and `ImageTexture` instances are owned by `WorldView` and freed cleanly on scene exit (avoiding ObjectDB leaks).

---

## 5. Risks, Compatibility Notes & Unresolved Decisions

### 5.1 Key Risks
1. **Legacy Test Coupling:** `test_fog_cloud_overlay.gd` and `test_fast_fog_mask_extended.gd` directly test `FogCloudLayer` internal methods (`_chunk_nodes`, `_layout_cache`, `_is_opaque_footprint_unexplored`, `_sync_full_fog_mask_ref/fast`), while `test_fog_rendering.gd` and `test_hybrid_boundary_visuals.gd` assert `fog_tile_layer` (`FogTileMapLayer`) tile states.
   - *Mitigation:* Decide in M2 whether `fog_tile_layer` is hidden/removed from `WorldView` or retained underneath/disabled, and whether `FogCloudLayer` class stays intact for unit tests while `WorldView` switches its active cloud presentation to `cloud_sea_base` + `cloud_sea_envelope.gdshader` (or updates tests explicitly if legacy layers are retired).
2. **Performance on Large Updates:** Full `128x128` (or higher-res envelope texture) evaluation over many sources per frame could spike frame time if a unit moves every frame.
   - *Mitigation:* Dirty-rect bounding-box updates (`update_dirty_rect`) + throttling/coalescing source updates per vision refresh tick.
3. **Preview vs `FogTileMapLayer` Visual Conflict:** If `fog_tile_layer` remains visible with opaque `alt=0` on `UNEXPLORED` cells, it will block the terrain preview inside the C1.9.1 organic envelope!
   - *Decision Needed:* In M2, `fog_tile_layer` must NOT draw opaque black/dark tiles over terrain-previewed `UNEXPLORED` cells (either `fog_tile_layer.visible = false` when C1.9.2 cloud sea is active, or `fog_tile_layer` is retired from `WorldView`).

### 5.2 Unresolved Decisions for Owner Sign-Off Before M1
1. **Legacy `fog_tile_layer` & `FogCloudLayer` Disposition:** Should `WorldView` disable/hide `fog_tile_layer` and `FogCloudLayer` sprite chunks when `C1.9.2` cloud sea envelope is active (keeping `FogCloudLayer` script intact for backward compatibility or retiring it in M3 with updated tests)?
2. **Preview Source Scope:** Should terrain preview sources be derived strictly from fixed/semi-fixed anchors (Town Hall, Outposts, Watchtowers, Territory, plus `FogOfWar` explored regions on load) or also follow moving tactical armies/scouts dynamically?
3. **Envelope Texture Resolution:** Confirm whether `1 texel = 1 map tile` (`128x128` with bilinear shader sampling, matching C1.9.1) or `2x` (`256x256`) is preferred for production.

---

**M0 Status:** Complete. Awaiting owner approval before beginning **M1 (`TerrainPreviewField`)**.
