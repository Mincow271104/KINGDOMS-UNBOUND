# C1.9.2 — M2-C1 Implementation Report: Terrain Preview GPU Renderer — WorldView Ownership Integration

**Project:** KINGDOMS UNBOUND  
**Engine:** Godot 4.7-stable  
**Milestone:** C1.9.2 — M2-C1 (WorldView Ownership Integration)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Status:** PASS — Ready for Owner Review (M2-C2 not started)

---

## 1. Baseline & Git Preservation Evidence

- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Pre-M2-C1 `git status --short` count:** `433` entries (preserved untouched).
- **M2-C1 Changes Only:**
  - **Modified:** `scripts/world/world_view.gd`
  - **Created:** `scripts/test/test_world_view_preview_lifecycle.gd`
  - **Created:** `docs/reports/C1_9_2_M2_C1_IMPLEMENTATION_REPORT.md`
- **Explicitly Untouched:** `fog_tile_layer` behavior, `fog_cloud_layer`, `cloud_sea_base`, `SaveManager`, `FogOfWar`, `DayNightModulate`, scenes, cloud shaders, and scratch assets. No staging, committing, or pushing performed.

---

## 2. Exact Implementation Changes (`scripts/world/world_view.gd`)

1. **Preloaded Script Types & Owned Fields (lines 57–64):**
   - `const TerrainPreviewFieldScript = preload("res://scripts/world/terrain_preview_field.gd")`
   - `const TerrainPreviewRendererScript = preload("res://scripts/world/terrain_preview_renderer.gd")`
   - `var terrain_preview_field: TerrainPreviewFieldScript = null`
   - `var terrain_preview_renderer: TerrainPreviewRendererScript = null`
   *(Using `preload()` avoids stale `global_script_class_cache.cfg` parse errors in headless/console runs, matching `WildlifeManagerScript` and `MonsterManagerScript` conventions.)*
2. **Lifecycle Integration:**
   - `_setup_fog_layer()` invokes `_setup_terrain_preview_renderer()` (covers both `_ready()` and `rebuild_world_terrain_for_load()`).
   - `_exit_tree()` invokes `cleanup_terrain_preview_renderer()`.
   - `_setup_terrain_preview_renderer()` creates/reconfigures `terrain_preview_field` with actual `map_width`, `map_height`, `world_data.seed` (fallback `world_seed`), and `fog_of_war`, ensures `terrain_preview_field.clear_sources()` (0 gameplay sources), attaches `terrain_preview_renderer` directly as a child of `WorldView` (`self`, independent of any cloud visual node), and calls `terrain_preview_renderer.configure(terrain_preview_field, 1)`.
   - `rebind_terrain_preview_fog(new_fog: FogOfWar = null)` provides the explicit Save/Load rebind hook for M2-C4.
   - `cleanup_terrain_preview_renderer()` calls `terrain_preview_renderer.cleanup()`, detaches and `queue_free()`s `terrain_preview_renderer`, and nulls both references.

---

## 3. Ownership & Lifecycle Design

- `WorldView` owns one `TerrainPreviewField` instance and one `TerrainPreviewRenderer` child `Node`.
- Neither `TerrainPreviewField` nor `TerrainPreviewRenderer` holds global mutable static state; independent `WorldView` instances own isolated fields, renderers, and `SubViewport`s.
- Repeated `_setup_fog_layer()` / `_setup_terrain_preview_renderer()` calls reuse the existing `TerrainPreviewRenderer` and `SubViewport` without creating duplicates.
- When no sources change, `terrain_preview_renderer` remains `SubViewport.UPDATE_DISABLED` with zero per-frame CPU or GPU envelope passes.

---

## 4. M2-C1 Lifecycle Test Results

Command (D3D12 Forward+):
```powershell
& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" -s "res://scripts/test/test_world_view_preview_lifecycle.gd"
```
Result: `exit=0`, **`PASS: test_world_view_preview_lifecycle.gd (16 assertions passed, 0 failed)`**.

Verified assertions:
- `WorldView` owns one `TerrainPreviewField` and one `TerrainPreviewRenderer`.
- Renderer and `SubViewport` configured to actual `128x128` `FogOfWar` dimensions.
- Empty source registry (`0` sources) preserved; valid `ViewportTexture` produced.
- Legacy `fog_tile_layer`, `fog_cloud_layer`, and `cloud_sea_base` remain enabled and unchanged.
- Repeated `_setup_fog_layer()` keeps `SubViewport` count at `1` (`vp_before=1`, `vp_after=1`) and reuses the same renderer.
- Idle `sync_if_needed()` executes `0` additional GPU passes and keeps `SubViewport.UPDATE_DISABLED`.
- `rebind_terrain_preview_fog()` updates `_fog_of_war` safely.
- `cleanup_terrain_preview_renderer()` frees `SubViewport` and clears references; reinitialization succeeds.
- Two independent `WorldView` instances do not share mutable field state.

---

## 5. Visual Screenshots & Findings

Captured before and after M2-C1 edits on D3D12 `12_0` Forward+ (`NVIDIA GeForce RTX 3050 Ti Laptop GPU`) at `1280x720`, `world_seed = 12345`, `06:00 (Bình minh)`:
- Before: `m2_c1_before.png` (`1280x720`)
- After: `m2_c1_after.png` (`1280x720`)

**Visual Findings:**
- Legacy `FogTileMapLayer`, `CloudSeaBase`, and `FogCloudLayer` appearance is identical before and after M2-C1.
- No additional dark overlay, rectangular boundary, flicker, or texture leak appears.
- HUD, minimap (`Fog: ON`), and `DayNightModulate` dawn tint remain unchanged.

---

## 6. Performance Measurements

Observed from `test_world_view_preview_lifecycle.gd` (D3D12 Forward+, `128x128` `1x`):
- `WorldView` full scene instantiation + init (`init_ms`): `1428.90 ms`
- Source data packing with `0` sources (`pack_0src`): `0.022 ms`
- Source texture upload (`upload`): `0.016 ms`
- `SubViewport` GPU time (`subGPU`, `0` sources): `0.000 ms` (and `0.013–0.016 ms` at `1` source in `test_terrain_preview_gpu_equiv.gd`)
- Idle GPU pass count: `0` additional passes (`UPDATE_DISABLED`)
- `SubViewport` count before / after repeated `_setup_fog_layer()`: `1` / `1`
- Envelope memory usage: `72 KB` (`8 KB` `128x2 RGBAF` + `64 KB` `128x128 RGBA8` `SubViewport`)
- Cleanup result: `SubViewport` freed (`not is_instance_valid(old_sub)`) and references cleared.

---

## 7. Known Limitations

- Pre-existing engine exit cleanup logs (`WARNING: 21 ObjectDB instances were leaked at exit` / `ERROR: 8 resources still in use at exit` on `WorldView` teardown) exist identically in baseline `m2_c1_before.png` and legacy `WorldView` tests; M2-C1's `cleanup_terrain_preview_renderer()` frees its own `SubViewport` cleanly.
- Envelope texture is not yet bound to any cloud composite node (intentionally deferred to M2-C2).

---

## 8. Save/Load Compatibility Assessment

- `SaveManager` was not modified in M2-C1.
- `WorldView.rebind_terrain_preview_fog(new_fog)` is in place so M2-C4 can safely rebind `terrain_preview_field` after `SaveManager` replaces `world_view.fog_of_war` and populates explored cells.

---

## 9. Regression Assessment

All 7 required suites passed with **0 failures** after final M2-C1 edits:

| Test Suite | Mode | Passed | Failed | Exit |
|---|---|---:|---:|---|
| `test_world_view_preview_lifecycle.gd` | D3D12 Forward+ | 16 | 0 | 0 |
| `test_terrain_preview_gpu_equiv.gd` | D3D12 Forward+ | 60 | 0 | 0 |
| `test_terrain_preview_field.gd` | Headless | 21 | 0 | 0 |
| `test_fog_of_war_reconnaissance.gd` | Headless | 127 | 0 | 0 |
| `test_save_load.gd` | Headless | 182 | 0 | 0 |
| `test_fog_debug_toggle.gd` | D3D12 Forward+ | 15 | 0 | 0 |
| `test_fog_cloud_overlay.gd` | D3D12 Forward+ | 61 | 0 | 0 |

---

## 10. Explicit Verdict

**PASS** — M2-C1 ownership, initialization, zero-source idle behavior, cleanup/reinitialization, and multi-instance isolation are verified with zero regressions and unchanged legacy visuals.

**STOPPING HERE. Awaiting owner review before starting M2-C2.**
