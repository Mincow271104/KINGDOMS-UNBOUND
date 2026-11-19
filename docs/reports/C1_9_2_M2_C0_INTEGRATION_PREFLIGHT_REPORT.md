# C1.9.2 — M2-C0 Production Integration Preflight Audit & Implementation Plan

**Project:** KINGDOMS UNBOUND  
**Engine:** Godot 4.7-stable  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Baseline HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** READ-ONLY AUDIT AND PLANNING ONLY  
**Status:** COMPLETE — Ready for Owner Review (M2-C1 not started)

---

## 1. Git Baseline & Preservation Evidence

- **Command:** `git rev-parse HEAD` -> `e1d379b93a48db018c7b412b896caa9592f6980c` (matches expected baseline).
- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`.
- **Pre-audit `git status --short` count:** `432` entries (all pre-existing modified/untracked files preserved untouched).
- **Safety compliance:** No `git reset`, `git clean`, `git stash`, `git checkout`, staging, commits, or pushes were executed. No production, test, scene, shader, or asset files were modified.

---

## 2. Exact Files Inspected

- `scripts/world/world_view.gd` (lines 53–72, 186–205, 377–550, 658–690, 981–990, 2529–2540, 4276–4530, 4632–4785, 4808–4875)
- `scripts/world/fog_cloud_layer.gd` (lines 1–125, 432–465, 522–718)
- `scripts/world/fog_of_war.gd` (API/enum scan)
- `scenes/world/world_view.tscn` (fog/day-night node hierarchy)
- `scripts/persistence/save_manager.gd` (lines 93, 397–406, 1880–1887, 2103–2124, 2272–2273, 2820–2830, 2876–2877, 2962–2965)
- `scripts/world/terrain_preview_field.gd` (lines 40–220, 489–558, 755)
- `scripts/world/terrain_preview_renderer.gd` (lines 1–213)
- `shaders/fog/terrain_preview_envelope.gdshader` (lines 1–73)
- `scripts/test/test_terrain_preview_gpu_equiv.gd` (lines 70–220)
- `scratch/c1_9_1_shape_correction/shaders/c1_9_1_envelope_cloud.gdshader` (lines 1–81)
- `scratch/c1_9_1_shape_correction/run_c1_9_1_prototype.gd` (lines 128–234)
- `scripts/world/wildlife_manager.gd` & `scripts/world/monster_manager.gd` (`refresh_visibility` / `FogOfWar` checks)
- `scripts/entities/citizen_controller.gd` (`citizen_id`) & `scripts/military/tactical_unit.gd` (`unit_id`, `is_alive`, `current_cell`)
- Legacy fog test callers: `scripts/test/test_fog_cloud_overlay.gd`, `scripts/test/test_fog_debug_toggle.gd`, `scripts/test/test_fog_rendering.gd`, `scripts/test/test_hybrid_boundary_visuals.gd`, `scripts/test/test_fog_debug_inspection.gd`.

---

## 3. Actual Current Architecture & Call Chains

### 3.1 Runtime Creation Order & Hierarchy (`world_view.gd` + `world_view.tscn`)
1. `scenes/world/world_view.tscn` defines `World` with child `DayNightModulate` (`CanvasModulate`, line 30).
2. `WorldView._ready()` initializes `fog_of_war = FogOfWar.new(world_data.map_width, world_data.map_height)` (line 377), reveals spawn (`reveal_circle(center_spawn, 10)`, line 378), connects `tactical_military_mgr` signals (`unit_moved`, `unit_spawned`, `unit_despawned`, lines 511–517), and calls `_setup_fog_layer()` (line 550).
3. `_setup_fog_layer()` (`lines 4276-4376`) frees any prior `fog_tile_layer`, `cloud_sea_base`, and `fog_cloud_layer`, then adds to `world_root` (`World`):
   - `fog_tile_layer` (`TileMapLayer`, `z_index = 5`): renders `UNEXPLORED` (`Color(0.04, 0.05, 0.08, 1.0)` with 16-tile fringe bitmask) and `EXPLORED`-not-`VISIBLE` (`Color(0.05, 0.07, 0.11, 0.56)`), and erases `VISIBLE` cells.
   - `fog_cloud_layer` (`FogCloudLayer`, `z_index = 7`): renders chunked `Sprite2D` clouds (`main_cloud_01..03.png`) over `UNEXPLORED` footprints and builds `_fog_mask_tex` (`FORMAT_RGBA8`).
   - `cloud_sea_base` (`Polygon2D`, `z_index = 6`): renders `cloud_sea_base_v4_512.png` + `cloud_sea_base_v5_wisps_512.png` masked by `fog_cloud_layer.get_fog_mask_texture()` with Bayer 4x4 dithering.
   - `CursorHighlight` sits at `z_index = 10`.
4. `sync_day_night_visuals()` (`lines 4849-4859`) updates `World/DayNightModulate.color` AND calls `fog_cloud_layer.apply_day_night_tint(cont_h)` (which mutates `fog_cloud_layer.modulate`, compounding with `DayNightModulate`).

### 3.2 Legacy Fog Callers
- `SaveManager` (`save_manager.gd:2273`): calls `world_view.call("set_debug_fog_disabled", false)` on load; calls `rebuild_world_terrain_for_load`, `sync_day_night_visuals`, `refresh_world_vision`, and `_sync_full_fog_and_minimap`.
- `HUD` (`hud.gd:349-351`): toggles `set_debug_fog_disabled`.
- Legacy tests (`test_fog_cloud_overlay.gd`, `test_fog_debug_toggle.gd`, `test_fog_rendering.gd`, `test_fog_debug_inspection.gd`, `test_hybrid_boundary_visuals.gd`): inspect `fog_tile_layer`, `cloud_sea_base`, `fog_cloud_layer`, `set_cloud_overlay_enabled`, `set_debug_fog_disabled`.

---

## 4. Fog Layer KEEP / REPLACE / DISABLE Decision Table

| Layer / Component | Current Role | Decision | Rationale |
|---|---|---|---|
| `FogOfWar` | Sole gameplay authority (`UNEXPLORED`, `EXPLORED`, `VISIBLE`) | **KEEP** | Non-negotiable gameplay & discovery authority. |
| `TerrainPreviewField` | CPU source registry, stable IDs, dirty tracking, `128x2` packing | **KEEP (Wire in M2-C)** | Approved M2-B foundation; no static mutable state (`static` methods are pure helpers). |
| `TerrainPreviewRenderer` | GPU `SubViewport` envelope generator (`UPDATE_DISABLED` when idle) | **KEEP (Wire in M2-C)** | Approved M2-B foundation; `0.012–0.321 ms` GPU on update, `0` passes when idle. |
| `CloudSeaComposite` (new `Polygon2D` + C1.9.1 shader) | Unified opaque cloud sea + preview veil | **ADD / REPLACE PRESENTATION** | Sole visual presentation of unexplored cloud sea & preview envelope. |
| `cloud_sea_base` (`Polygon2D`, `z_index = 6`) | Legacy v4/v5 tiled cloud sea | **DISABLE / REPLACE** | Would duplicate cloud sea and create rectangular `fog_mask` seams. |
| `fog_cloud_layer` (`FogCloudLayer`, `z_index = 7`) | Legacy chunked `Sprite2D` clouds + `_fog_mask_tex` | **DISABLE** (retain script/assets on disk) | Would render over previewed terrain and double-accumulate alpha. Note: `FogCloudLayer` also has `static` caches (`_layout_cache`, `_fg_cloud_material`), so disabling it avoids static cross-instance leakage. |
| `fog_tile_layer` (`TileMapLayer`, `z_index = 5`) | Legacy dark `UNEXPLORED` + `EXPLORED` tiles | **DISABLE VISUALS (or hide when composite active)** | Rendering dark `UNEXPLORED` tiles at `z=5` under `CloudSeaComposite` creates the exact rectangular inner border rejected in C1.9.1. Keep API/node safe or update legacy visual tests in M2-C2/M2-C5. |

---

## 5. Renderer Ownership & Lifecycle Proposal

- **Owner:** `WorldView` owns `terrain_preview_field: TerrainPreviewField` (RefCounted) and `terrain_preview_renderer: TerrainPreviewRenderer` (child `Node` of `WorldView`, or `World`, with `cleanup()` on `_exit_tree()` and `_setup_fog_layer()`).
- **Reconfiguration on Rebuild:** `_setup_fog_layer()` calls `terrain_preview_field.configure(mw, mh, world_seed, res_scale, fog_of_war)` and `terrain_preview_renderer.configure(terrain_preview_field, res_scale)` without duplicating `SubViewport` nodes (verified safe by `test_terrain_preview_gpu_equiv.gd`).
- **Zero Sources:** `terrain_preview_envelope.gdshader` outputs `p_sd = 9999.0`, `c_sd = 9999.0` -> `r = 1.0, g = 1.0` when `source_count == 0`, rendering full opaque cloud sea cleanly.
- **Multiple `WorldView` Instances:** Inspected `terrain_preview_field.gd` and `terrain_preview_renderer.gd`: neither class holds any `static var` mutable cache. Each `WorldView` owns isolated instances.

---

## 6. Source Registration Lifecycle Proposal

Use deterministic, entity-owned stable IDs (reconciled inside `WorldView.refresh_world_vision()` and `_sync_full_fog_and_minimap()`, with coalesced `terrain_preview_renderer.sync_if_needed()` once per vision refresh):

| Category | Source | Stable ID Convention | Lifecycle Events |
|---|---|---|---|
| `TOWN_HALL` | Active Town Hall (`BuildingSystem.is_town_hall_active(world_data)`) | `"town_hall"` | Registered at `world_data.center_spawn` when Town Hall is active; removed if Town Hall is inactive/destroyed. |
| `HUNTER_SCOUT` | Citizens in `citizen_list` with `can_scout_beyond_territory == true` | `"hunter:" + cit.citizen_id` | Registered/updated at `cit.current_cell` (with facing direction if available, else `Vector2.ZERO`); removed when role changes (`_on_citizen_role_changed` -> `refresh_world_vision()`), citizen dies, or is removed from `citizen_list`. |
| `SOLDIER` | Living units in `tactical_military_mgr.get_all_units()` (`is_alive == true`), or fallback `player_army_mgr` (`soldier_count > 0`) | `"soldier:" + u.unit_id` (or `"army:player"` fallback) | Updated on `unit_moved` (`_on_tactical_unit_moved` -> `refresh_world_vision()`); removed on death/despawn (`_on_tactical_unit_despawned`); multiple units sharing a cell coalesce cleanly via `smin_poly` or deduplication. |

**Reconciliation Pattern:** Compute desired active ID set during `refresh_world_vision()`, remove any stale IDs no longer in the desired set, upsert/update desired IDs (relying on `TerrainPreviewField`'s `_sources_equal()` dirty check), and call `terrain_preview_renderer.sync_if_needed()` **once** at the end.

---

## 7. Coordinate-Space Verification

Verified exact mathematical alignment across all 3 stages:
1. **CPU (`TerrainPreviewField`):** `IsoMath.map_to_local(cell)` uses `TILE_WIDTH = 32`, `TILE_HEIGHT = 16` (`HALF_WIDTH = 16`, `HALF_HEIGHT = 8`).
2. **GPU Envelope (`shaders/fog/terrain_preview_envelope.gdshader:19-20`):**
   - `uv_grid = UV * map_size - 0.5` -> texel `(x, y)` center maps to `uv_grid = (x, y)`.
   - `p_iso = vec2((uv_grid.x - uv_grid.y) * 16.0, (uv_grid.x + uv_grid.y) * 8.0)`.
3. **Cloud Composite (`c1_9_1_envelope_cloud.gdshader:14, 24-26`):**
   - `v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy` (world-space, invariant to `Camera2D` zoom/pan).
   - `u_grid = (v_world_pos.x / 32.0) + (v_world_pos.y / 16.0)`, `v_grid = (v_world_pos.y / 16.0) - (v_world_pos.x / 32.0)`.
   - `mask_uv = (vec2(u_grid, v_grid) + 0.5) / map_size`.
- **Result:** **Zero half-pixel or axis mismatch.** `Polygon2D` bounds `(-0.5, -0.5)` to `(mw - 0.5, mh - 0.5)` in grid space map `[0, 1]` UV cleanly, and `repeat_disable` + shader fallback (`preview_sd = 300.0`) handles border padding safely.
- **Asset Promotion Required in M2-C2:** `c1_9_1_envelope_cloud.gdshader` uses `sea_tex` (`cloud_wisps_sea_1024.png`) and `bank_tex` (`cloud_banks_macro_1024.png`), currently located in `scratch/c1_8_cloud_reference_redesign/assets/`. They must be promoted to `res://assets/fog/` in M2-C2.

---

## 8. Day/Night Tint Authority

- `scenes/world/world_view.tscn:30` places `DayNightModulate` (`CanvasModulate`) on `World`.
- All `CanvasItem` children of `World` automatically inherit `DayNightModulate.color`.
- **Rule for M2-C4:** `World/DayNightModulate` MUST be the **single RGB tint authority** for `CloudSeaComposite`. Do **not** add a second `modulate` or `tint_rgb` uniform on `CloudSeaComposite` (unlike legacy `fog_cloud_layer.apply_day_night_tint()` which double-multiplied `modulate` on top of `CanvasModulate`). Alpha (`COLOR.a`) remains strictly controlled by `c1_9_1_envelope_cloud.gdshader`.

---

## 9. Save/Load Lifecycle & Rebind Risks

Observed call sequence in `scripts/persistence/save_manager.gd`:
1. Line 2104: `world_view.rebuild_world_terrain_for_load(...)` -> calls `_setup_fog_layer()` (line 681).
2. Line 2124: `world_view.set("fog_of_war", FogOfWar.new(target_width, target_height))` — **replaces `fog_of_war` AFTER `_setup_fog_layer()`!**
3. Line 2824–2830: restores `fog_of_war` explored cells.
4. Line 2877: `world_view.sync_day_night_visuals()`.
5. Line 2963–2965: `world_view.refresh_world_vision()` and `world_view._sync_full_fog_and_minimap()`.

**Mitigation for M2-C4:**
- Never cache a stale `FogOfWar` reference without rebinding: `_sync_full_fog_and_minimap()` / `refresh_world_vision()` must update `terrain_preview_field.set_fog_of_war(fog_of_war)`, reconcile all live entities (Town Hall, Hunters, Soldiers), call `terrain_preview_renderer.sync_if_needed()`, and ensure `CloudSeaComposite`'s `ShaderMaterial` has the current `terrain_preview_renderer.get_envelope_texture()` bound.
- No save schema changes are needed.

---

## 10. Gameplay Visibility Leakage Analysis

Verified from source code that previewed terrain **cannot** leak gameplay objects:
- **Props:** `world_view.gd:917, 4518, 4645, 4676` -> `p_node.visible = debug_fog_disabled or (fog_of_war != null and fog_of_war.is_explored(cell))`.
- **POIs:** `world_view.gd:989` -> `p_node.visible = should_debug_reveal_category("poi") or (poi.state != POIManager.POIState.UNDISCOVERED)` (discovered via `poi_mgr.update_discovery(fog_of_war, ...)`).
- **Wildlife:** `wildlife_manager.gd:432` -> `actor.visible = debug_fog_disabled or (fog_of_war != null and fog_of_war.is_visible(c))`.
- **Monsters & Nests:** `monster_manager.gd:1059, 1068` -> nests use `fog.is_explored(c)` / `discovered`; monsters use `fog.is_visible(ma.current_cell)`.
- **Enemy Military & Siege Objectives:** `world_view.gd:4694, 4700` -> enemies use `fog_of_war.is_visible(ec)`, siege objectives use `fog_of_war.is_explored(oc)`.

All entity visibility remains 100% gated by `FogOfWar`.

---

## 11. Recommended M2-C1 through M2-C5 Implementation Sequence

### M2-C1 — Renderer Ownership & WorldView Integration
- **Goal:** `WorldView` instantiates, configures, and cleans up `TerrainPreviewField` and `TerrainPreviewRenderer`, keeping it `UPDATE_DISABLED` when idle and reconfiguring cleanly on `rebuild_world_terrain_for_load()`. No visual replacement yet.
- **Files:** `scripts/world/world_view.gd`, new focused lifecycle test `scripts/test/test_world_view_preview_lifecycle.gd`.
- **Rollback Boundary:** Isolated to two new fields and `_setup_fog_layer()` / `_exit_tree()` hooks in `world_view.gd`.

### M2-C2 — Cloud Composite Integration
- **Goal:** Promote `cloud_wisps_sea_1024.png` and `cloud_banks_macro_1024.png` to `res://assets/fog/`, add production `shaders/fog/cloud_sea_composite.gdshader` (based on `c1_9_1_envelope_cloud.gdshader`), create `CloudSeaComposite` `Polygon2D` in `world_view.gd`, bind `envelope_tex`, and disable legacy `fog_tile_layer` / `cloud_sea_base` / `fog_cloud_layer` visuals in normal play so there is zero duplicate fog or rectangular inner border. Update/reconcile affected legacy visual tests.
- **Files:** `assets/fog/cloud_wisps_sea_1024.png`, `assets/fog/cloud_banks_macro_1024.png`, `shaders/fog/cloud_sea_composite.gdshader`, `scripts/world/world_view.gd`, legacy fog tests if asserting on disabled layers.
- **Rollback Boundary:** Feature-isolated to `CloudSeaComposite` setup & visibility toggle in `world_view.gd`.

### M2-C3 — Preview Source Lifecycle
- **Goal:** Connect Town Hall (`"town_hall"`), Hunter/scout (`"hunter:<citizen_id>"`), and living Soldier (`"soldier:<unit_id>"` / `"army:player"`) reconciliation in `WorldView.refresh_world_vision()` and `_sync_full_fog_and_minimap()`, coalescing all updates into one `terrain_preview_renderer.sync_if_needed()` call. Ensure role changes (`_on_citizen_role_changed`) trigger `refresh_world_vision()`.
- **Files:** `scripts/world/world_view.gd`, new/extended source-lifecycle test.
- **Rollback Boundary:** Source reconciliation helper in `world_view.gd`.

### M2-C4 — Day/Night, Save/Load & Lifecycle Hardening
- **Goal:** Ensure `World/DayNightModulate` is the sole RGB tint authority on `CloudSeaComposite`, rebind `fog_of_war` & `envelope_tex` after `SaveManager.load_game()`, verify `set_debug_fog_disabled()` toggles `CloudSeaComposite.visible`, and verify zero stale/duplicate `SubViewport`s on repeated rebuilds.
- **Files:** `scripts/world/world_view.gd` (no `SaveManager` schema changes).
- **Rollback Boundary:** Rebind & visibility hooks in `world_view.gd`.

### M2-C5 — Visual Acceptance & Regression
- **Goal:** End-to-end D3D12 visual & automated verification across all required scenarios and zoom levels (`0.75x`, `1.0x`, `1.5x`, `2.2x`).
- **Files:** Visual acceptance script/report under `scripts/test/` and `docs/reports/`.

---

## 12. Performance Acceptance Targets (Grounded in M2-B Benchmarks)

| Metric | Target | Observed M2-B Evidence (`test_terrain_preview_gpu_equiv.gd`, D3D12 Forward+) | Status |
|---|---|---|---|
| Source mutation CPU submission (`pack` + `upload`) | `< 0.2 ms` (1–64 sources) | `1x` 1–64 sources: `0.029–0.127 ms` pack + `0.012–0.018 ms` upload (`0.041–0.145 ms` med); `128` sources: `0.260 ms` pack + `0.018 ms` upload (`0.278 ms` med) | **Achievable** (note: `128` worst-case pack is ~`0.275 ms`, still sub-0.3 ms). |
| Idle renderer | `0` envelope GPU passes | `UPDATE_DISABLED`, `+0` passes verified across 10/10 benchmark configs | **Verified** |
| Single / coalesced change | `1` coalesced GPU pass | 5 rapid updates -> `1` GPU pass verified | **Verified** |
| Unchanged source data | `0` full rebuilds | `_sources_equal()` + `_gpu_dirty` skips unchanged updates | **Verified** |
| Per-frame CPU SDF generation | `0` | All envelope generation runs on GPU `SubViewport` on dirty frames only | **Verified** |
| Composite shader GPU cost | Report measured result | To be measured in M2-C2/M2-C5 on D3D12 Forward+ | **Deferred to M2-C2** |

---

## 13. Regression Commands

- `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" -s "res://scripts/test/test_terrain_preview_gpu_equiv.gd"`
- `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s "res://scripts/test/test_terrain_preview_field.gd"`
- `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s "res://scripts/test/test_fog_of_war_reconnaissance.gd"`
- `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s "res://scripts/test/test_save_load.gd"`
- `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" -s "res://scripts/test/test_fog_debug_toggle.gd"`
- `& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" -s "res://scripts/test/test_fog_cloud_overlay.gd"`

---

## 14. Visual Acceptance Checklist (M2-C5)

- [ ] Initial settlement: softly rounded, slightly asymmetric organic preview island; no rectangular borders.
- [ ] Deep unexplored terrain: 100% opaque luminous cloud sea, zero terrain/entity bleed-through.
- [ ] Town Hall expansion: smooth envelope growth.
- [ ] Hunter movement: directional preview lobe follows movement; gameplay entities remain `FogOfWar`-gated.
- [ ] Soldier movement & old-position cleanup: new position revealed, old position cleanly re-covered by cloud sea.
- [ ] Overlapping sources & source removal: smooth `smin_poly` union and clean retraction on removal.
- [ ] Day / Dusk / Night: single `DayNightModulate` tint, preserved cloud alpha.
- [ ] Save / Load: envelope, sources, and `FogOfWar` restore identically with no stale texture.
- [ ] Zoom levels `0.75x`, `1.0x`, `1.5x`, `2.2x`: world-locked `v_world_pos`, no swimming or seams.
- [ ] Debug fog disabled / enabled: toggles `CloudSeaComposite` cleanly without altering `FogOfWar` state.

---

## 15. Risks, Blockers & Unresolved Questions

1. **Legacy Visual Test Contracts:** `test_fog_cloud_overlay.gd`, `test_fog_rendering.gd`, `test_fog_debug_toggle.gd`, and `test_hybrid_boundary_visuals.gd` currently assert on `fog_tile_layer.visible`, `cloud_sea_base`, and `fog_cloud_layer`. M2-C2 must decide whether to update those visual tests to target `CloudSeaComposite` or keep a headless-only compatibility flag while `CloudSeaComposite` is the sole active gameplay presentation.
2. **Asset Promotion:** `cloud_wisps_sea_1024.png` and `cloud_banks_macro_1024.png` currently reside in `scratch/c1_8_cloud_reference_redesign/assets/` and must be copied into `res://assets/fog/` in M2-C2.
3. **128-Source Pack Cost:** At 128 active sources, `pack_sources_into_rgba32f()` measures `0.256–0.275 ms` (slightly above `0.2 ms`, though well under 1% of a 16.6 ms frame).

---

## 16. Explicit Recommendation

**READY WITH WARNINGS** — Architecture, coordinate alignment, `FogOfWar` isolation, and M2-B GPU foundation are verified ready for **M2-C1**. The only warnings to track during M2-C2/M2-C3 are: (1) promoting the two C1.9.1 cloud textures from `scratch/` to `res://assets/fog/`, (2) updating legacy fog visual tests when disabling legacy fog layers, and (3) ensuring `World/DayNightModulate` remains the sole RGB tint authority.

**STOPPING HERE. Awaiting owner approval before starting M2-C1.**
