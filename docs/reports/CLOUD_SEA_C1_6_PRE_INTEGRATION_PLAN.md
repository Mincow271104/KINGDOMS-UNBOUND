# KINGDOMS UNBOUND — C1.6 Production Integration Plan
## Pre-Integration Audit, Equivalence Evidence & Implementation Sequence

**Role:** Senior Godot Architect, Rendering Engineer, Performance Engineer, Regression Reviewer  
**Engine:** Godot 4.7 (`Forward+`, `TEXTURE_FILTER_NEAREST`)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Baseline HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** Read-Only Pre-Integration Audit (Zero production edits)

---

## 1. Executive Recommendation

**Status: READY FOR CONTROLLED C1.6 PRODUCTION INTEGRATION**, subject to fixing one newly identified Save/Load dimension-mismatch rebinding risk and updating three coupled assertions in `test_fog_cloud_overlay.gd`.

- **V5 MultiScale `CloudSeaBase`:** Safe to integrate at `z_index = 6` inside `World` (between `FogTileMapLayer` at `z = 5` and `FogCloudLayer` at `z = 7`). World-space UV mapping `(u_grid, v_grid) -> mask_uv` scales dynamically with `uniform vec2 map_size` and works for any map size (`64×64`, `128×128`, `256×256+`).
- **Foreground Version A (`main_cloud_01..03.png`) + `A_Medium`:** Safe to promote from `scratch/c1_1_refined/` into `assets/fog/` and configure in `FogCloudLayer` (`z_index = 7`).
- **Fast Fog Mask (2-Pass `PackedByteArray` L1 Distance Transform):** **Verified 100% byte-equivalent** to the `7×7` reference implementation (`eq_ref = true`, `inc_matches_full = true`, zero explored/visible leaks) across `64×64`, `128×128`, and `256×256` maps, delivering a **66.8×–70.3× full-sync speedup** and **`~0.20 ms` incremental dirty-rect updates**.
- **Day/Night Tint Fix:** `World/DayNightModulate` (`CanvasModulate`) must be the **single RGB tint authority**. Keeping `FogCloudLayer.apply_day_night_tint()` RGB-neutral (`Color(1.0, 1.0, 1.0, alpha)`) preserves the public API signature while eliminating double-tinting across `DAY`, `DAWN`, `DUSK`, and `NIGHT`.

---

## 2. Exact Production Files Requiring Changes (In C1.6)

### Assets to Add / Promote (No Existing Assets Overwritten)
- `assets/fog/cloud_sea_base_v4_512.png` *(copied from C1.5.5 scratch)*
- `assets/fog/cloud_sea_base_v5_wisps_512.png` *(copied from C1.5.5 scratch)*
- `assets/fog/main_cloud_01_towering_cumulus.png` (`144×92`, *copied from `scratch/c1_1_refined/`*)
- `assets/fog/main_cloud_02_sweeping_bank.png` (`160×84`, *copied from `scratch/c1_1_refined/`*)
- `assets/fog/main_cloud_03_asymmetrical_cluster.png` (`136×88`, *copied from `scratch/c1_1_refined/`*)

> **Note:** Existing `assets/fog/cloud_*.png` (`48×48`) files remain untouched on disk to avoid breaking any legacy references until explicitly retired.

### Scripts to Modify
1. `scripts/world/fog_cloud_layer.gd`
   - Move `z_index` from `6` to `7` (preserving `FogTileMapLayer z=5 -> CloudSeaBase z=6 -> FogCloudLayer z=7 -> CursorHighlight z=10`).
   - Add `CloudSeaBase` (`Polygon2D` + `ShaderMaterial` + `fog_mask` `Image`/`ImageTexture`) management with 2-pass `PackedByteArray` full + incremental dirty-rect mask sync.
   - Switch foreground sprite placement to Version A (`main_cloud_01..03.png`) at `A_Medium` density.
   - Neutralize RGB modulation in `apply_day_night_tint()` while preserving the method signature and alpha (`0.93–0.96`).
2. `scripts/world/world_view.gd`
   - Ensure `fog_cloud_layer` is re-bound/reconfigured if `fog_of_war` is replaced (e.g., during Save/Load map-size change) and verify `_sync_full_fog_and_minimap()` / `_update_fog_visuals()` / `set_debug_fog_disabled()` drive both `CloudSeaBase` and `FogCloudLayer` cleanly.
3. `scripts/persistence/save_manager.gd` *(minimal 1–3 line lifecycle guard, **zero save-schema changes**)*
   - After replacing `world_view.fog_of_war` on dimension mismatch (`lines 2122–2124`), ensure `fog_cloud_layer.configure(...)` or `world_view._setup_fog_layer()` rebinds the new `FogOfWar` instance before `_sync_full_fog_and_minimap()`.
4. `scripts/test/test_fog_cloud_overlay.gd`
   - Update assertions that currently hardcode C1 prototype assumptions: `z_index == 6 -> 7` (`line 126`), `48×48` texture size (`line 25`), and distinct RGB modulation in `apply_day_night_tint()` (`line 112`).

---

## 3. Proposed Implementation Order (Smallest Safe Sequence)

| Step | Sub-Milestone | Scope | Verification Gate |
| :--- | :--- | :--- | :--- |
| **1** | **C1.6.1 — Assets & `FogCloudLayer` Mask Engine** | Promote V5 + Version A PNGs to `assets/fog/`; add 2-pass `PackedByteArray` full + dirty-rect mask methods to `fog_cloud_layer.gd` (unit-tested in isolation). | `test_fast_fog_mask_extended.gd` passes (`64×64`, `128×128`, `256×256`). |
| **2** | **C1.6.2 — `CloudSeaBase` Shader & Layer Order (`z=6` / `z=7`)** | Mount `CloudSeaBase` `Polygon2D` at `z_index = 6` under `World` (or as `z=-1` child of `FogCloudLayer` at `z=7`, wait — keeping `CloudSeaBase` at `z=6` and `FogCloudLayer` at `z=7` directly under `World` matches the exact required hierarchy). | `test_fog_rendering.gd`, `test_fog_debug_toggle.gd`, `test_fog_cloud_overlay.gd`. |
| **3** | **C1.6.3 — Foreground Version A + `A_Medium`** | Swap `CLOUD_TEXTURE_PATHS` & chunk candidate logic to `main_cloud_01..03.png` at `A_Medium`. | Visual & coverage check; `test_fog_cloud_overlay.gd`. |
| **4** | **C1.6.4 — Day/Night Single-Authority Tint Fix** | Make `apply_day_night_tint()` RGB-neutral `(1, 1, 1, alpha)` while keeping `World/DayNightModulate` as single tint authority. | `test_day_night_phase1.gd`, `test_day_night_phase2.gd`, visual 4-TOD check. |
| **5** | **C1.6.5 — Save/Load Rebind Guard & Full Regression** | Fix `save_manager.gd:2124` / `world_view.gd` rebind on dimension change; run full fog, save/load, and gameplay regression suite. | All regression suites pass (`0` failures). |

---

## 4. Dependency & Ownership Map (Verified)

| Component / Node | Owner / Parent | `z_index` | Verified Callers & Dependencies |
| :--- | :--- | :---: | :--- |
| `FogOfWar` (`RefCounted`) | `WorldView.fog_of_war` | — | `WorldView`, `SaveManager` (`lines 397, 2124, 2824`), `FogCloudLayer._fog_of_war`, `Minimap`. |
| `FogTileMapLayer` (`TileMapLayer`) | `WorldView/World` | **`5`** | `WorldView._setup_fog_layer()`, `_sync_fog_cell()`, `_update_fog_visuals()`, `set_debug_fog_disabled()`. Tested by `test_fog_rendering.gd`, `test_fog_debug_toggle.gd`. |
| **`CloudSeaBase` (`Polygon2D`)** *(Proposed)* | `WorldView/World` (managed by `WorldView` or `FogCloudLayer` handle) | **`6`** | Reads `fog_mask` (`ImageTexture`), `cloud_sea_base_v4_512.png`, `cloud_sea_base_v5_wisps_512.png`. Toggled by `debug_fog_disabled` & `set_cloud_overlay_enabled()`. |
| `FogCloudLayer` (`Node2D`) | `WorldView/World` | **`7`** *(currently `6`)* | `WorldView._setup_fog_layer()`, `_sync_full_fog_layer()`, `_update_fog_visuals()`, `sync_day_night_visuals()`, `set_cloud_overlay_enabled()`, `set_cloud_density_preset()`. |
| `CursorHighlight` (`Sprite2D`) | `WorldView/World` | **`10`** | `scenes/world/world_view.tscn:27–28`; remains above all fog/cloud layers. |
| `DayNightModulate` (`CanvasModulate`) | `WorldView/World` | — | `scenes/world/world_view.tscn:30`; tints all `World/*` children; `WorldView.sync_day_night_visuals()` (`line 4738`). |
| `HUD` (`CanvasLayer`) | `WorldView` (sibling of `World`) | CanvasLayer | Outside `World/DayNightModulate` scope (`test_day_night_phase1.gd:126`). |

---

## 5. CloudSeaBase Integration Design (Part A)

- **Scene Parent & Z-Index:** `CloudSeaBase` (`Polygon2D`) added as a child of `WorldView/World` with `z_index = 6` and `texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST`. Preserves `FogTileMapLayer (z=5)` < `CloudSeaBase (z=6)` < `FogCloudLayer (z=7)` < `CursorHighlight (z=10)` < `HUD (CanvasLayer)`.
- **Polygon Geometry & Dynamic Map Sizes:** Computed from `FogOfWar.map_width` (`mw`) and `FogOfWar.map_height` (`mh`) using continuous isometric corners (`_cont_map_to_local(fx, fy)` with a `-1.5 .. +0.5` cell pad):
  - `p0 = _cont_map_to_local(-1.5, -1.5)`
  - `p1 = _cont_map_to_local(mw + 0.5, -1.5)`
  - `p2 = _cont_map_to_local(mw + 0.5, mh + 0.5)`
  - `p3 = _cont_map_to_local(-1.5, mh + 0.5)`
  - Works identically for `64×64`, `128×128`, `256×256`, or non-square maps because shader `uniform vec2 map_size = vec2(float(mw), float(mh))` scales `mask_uv` dynamically.
- **V5 Textures & Uniforms:**
  - `base_tex`: `res://assets/fog/cloud_sea_base_v4_512.png` (`repeat_enable, filter_nearest`, `tex_scale = 512.0`).
  - `wisp_tex`: `res://assets/fog/cloud_sea_base_v5_wisps_512.png` (`repeat_enable, filter_nearest`, `wisp_scale = 640.0`, offset `vec2(0.37, 0.19)`, mixed via `wcol.a * 0.85`).
  - `fog_mask`: `ImageTexture` (`FORMAT_RGBA8`, `repeat_disable, filter_linear`).
- **World-Space UV & Camera Movement:** `v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy` in `vertex()` maps world-space coordinates directly, so panning/zooming `Camera2D` never causes texture swimming or UV drift.
- **Resource Lifetime & Cleanup:** `_fog_mask_img`, `_fog_mask_tex`, `ShaderMaterial`, and `CloudSeaBase` are owned by `FogCloudLayer` / `WorldView` and freed via `queue_free()` in `_setup_fog_layer()` before rebuilding (matching existing `fog_tile_layer` / `fog_cloud_layer` cleanup at `world_view.gd:4276–4281`).

---

## 6. Fog Mask Equivalence Test Plan & Results (Part B)

Executed standalone validation script `scratch/c1_6_audit/test_fast_fog_mask_extended.gd` in Godot 4.7 headless across `64×64`, `128×128`, and `256×256` maps covering all 7 required scenarios:
- Empty exploration (`100% UNEXPLORED`)
- Boundary-adjacent reveals (`(0,0)`, `(dim-1,0)`, `(0,dim-1)`, `(dim-1,dim-1)`, edge strips)
- Multiple disconnected explored regions + `update_observers([], 0)` degradation + overlapping scout pocket
- Repeated reveals on already-explored/visible cells
- Incremental dirty-rect 2-pass update (`±3` write box + `±3` read margin) vs. full rebuild (`inc_matches_full`)
- Simulated Save/Load rebuild (`EXPLORED` restore + `recompute_vision`)
- Fully explored map (`100% EXPLORED`)

### Observed Results

| Map Size | Reference `7×7` (ms) | Fast 2-Pass Full (ms) | Full Speedup | Incremental Dirty (ms) | `eq_ref` & Zero-Leak | `inc_matches_full` | Peak CPU Memory (`dist` + `rgba`) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`64×64`** | `128.15` | **`1.89`** | **67.8×** | **`0.18`** | **PASS (`0` leaks)** | **`true`** | `4 KB + 16 KB = 20 KB` |
| **`128×128`** | `596.98` | **`8.49`** | **70.3×** | **`0.21`** | **PASS (`0` leaks)** | **`true`** | `16 KB + 64 KB = 80 KB` |
| **`256×256`** | `2374.68` | **`35.56`** | **66.8×** | **`0.20`** | **PASS (`0` leaks)** | **`true`** | `64 KB + 256 KB = 320 KB` |

**Result:** `PASS: test_fast_fog_mask_extended.gd (all equivalence & zero-leak checks passed)`. Exact byte-for-byte equivalence holds across all 21 checks.

---

## 7. Day/Night Tint Correction Design (Part C)

### Verified Callers of `FogCloudLayer.apply_day_night_tint()`
1. `scripts/world/world_view.gd:4747` (`sync_day_night_visuals()`) — calls `fog_cloud_layer.apply_day_night_tint(cont_h)` right after setting `World/DayNightModulate.color = get_ambient_color_for_time(cont_h)`.
2. `scripts/test/test_fog_cloud_overlay.gd:106, 108, 110` — unit test calling `apply_day_night_tint(12.0 / 18.75 / 22.0)` directly.
- **No other production callers exist.**

### Minimal-Risk Change Proposal
- Keep `apply_day_night_tint(continuous_hour: float) -> void` on `FogCloudLayer` so no caller signature breaks.
- Set `modulate` RGB to **`1.0, 1.0, 1.0`** across all phases (`DAY`, `DAWN`, `DUSK`, `NIGHT`), preserving only the subtle alpha curve (`0.93` dawn, `0.94` day/dusk, `0.96` night) — or `0.94` uniform if desired — and keep `CloudSeaBase.modulate = Color.WHITE` (`base_alpha = 0.96` in shader).
- Update `test_fog_cloud_overlay.gd:112` to assert RGB neutrality (`modulate.r == 1.0 and modulate.g == 1.0 and modulate.b == 1.0`) and valid alpha (`0.90..1.0`) rather than distinct RGB multipliers.
- **Verified Effect:** `World/DayNightModulate` tints the entire `World` subtree cleanly once (`DAWN (0.97, 0.835, 0.72)`, `DAY (1, 1, 1)`, `DUSK (0.95, 0.66, 0.48)`, `NIGHT (0.52, 0.60, 0.84)`), matching C1.5.5 visual captures.

---

## 8. Save/Load & Lifecycle Risks (Part D)

1. **HIGH — Stale `FogOfWar` Reference on Dimension-Changing Save/Load (`save_manager.gd:2122–2124`):**
   - `WorldView.rebuild_world_from_seed()` (`world_view.gd:677`) calls `_setup_fog_layer()` *before* `SaveManager` checks dimension mismatch at `save_manager.gd:2123–2124` and replaces `world_view.fog_of_war = FogOfWar.new(target_width, target_height)`.
   - Consequently, `fog_cloud_layer._fog_of_war` (and `CloudSeaBase` polygon/mask dimensions) would still reference the old-dimension `FogOfWar` object.
   - **Mitigation:** In C1.6, ensure `SaveManager` calls `world_view._setup_fog_layer()` (or `fog_cloud_layer.configure(...)`) *after* `fog_of_war` replacement, or have `_sync_full_fog_and_minimap()` verify `fog_cloud_layer._fog_of_war == fog_of_war` and resize/reconfigure if mismatched.
2. **Mask Created Before First Shader Draw:** Create `_fog_mask_img` and `_fog_mask_tex` synchronously inside `_setup_fog_layer()` / `configure()` before attaching `ShaderMaterial` to `CloudSeaBase` so the shader never samples a null texture on frame 1.
3. **Duplicate Nodes / Signal Connections:** `_setup_fog_layer()` already frees `fog_tile_layer` and `fog_cloud_layer` before recreating; mirror this exact pattern for `CloudSeaBase` (either as a tracked `WorldView` node freed alongside `fog_cloud_layer`, or owned/freed by `FogCloudLayer`). No new signals are needed.
4. **Save Schema:** **Zero schema changes.** `SaveManager` continues saving/loading `fog_of_war` as an array of `[x, y]` explored coordinates (`save_manager.gd:396–406, 2822–2838`).

---

## 9. Regression Matrix (Part E)

| Suite / Check | Baseline Status (Observed) | C1.6 Coverage & Notes |
| :--- | :--- | :--- |
| `scripts/test/test_fog_rendering.gd` | **PASS (24/24)** | Verifies A2 `FogTileMapLayer`, `64×64` V3 + `128×128` V6 Save/Load, reveal/degrade semantics. |
| `scripts/test/test_fog_debug_toggle.gd` | **PASS (15/15)** | Verifies `set_debug_fog_disabled()` hides fog & clouds without mutating `FogOfWar`. Must also assert `CloudSeaBase.visible` toggles. |
| `scripts/test/test_fog_cloud_overlay.gd` | **PASS (all)** | **Requires C1.6 test updates** for `z_index = 7`, Version A dimensions, and RGB-neutral `apply_day_night_tint()`. |
| `scripts/test/test_day_night_phase1.gd` | **PASS (42/42)** | Verifies `World/DayNightModulate` and `HUD` isolation across all phases & Save/Load. |
| `test_fast_fog_mask_extended.gd` *(scratch -> promote to `scripts/test/`)* | **PASS (all)** | Verifies `eq_ref`, `inc_matches_full`, zero leaks across `64×64`, `128×128`, `256×256`. |
| `test_save_load.gd`, `test_repeated_save_load_scene_cleanup.gd`, `test_world_size_compatibility.gd` | *Not run in this read-only audit* | Must be run in C1.6 after integration to verify scene cleanup, Save/Load, and map-size switching. |
| Gameplay / UI (`CursorHighlight`, placement previews, camera pan/zoom) | *Visual in C1.5.5* | Verify `z=10` `CursorHighlight` and building previews render cleanly above `z=6` / `z=7` in C1.6. |

> **Known Baseline Warnings (Unrelated to C1.6):** All four existing headless suites log `WARNING: 21–35 ObjectDB instances were leaked at exit` and `ERROR: 8 resources still in use at exit` on `SceneTree.quit()`. Running `test_fog_cloud_overlay.gd` in Godot 4.7 also generated an untracked `.uid` file (`scripts/test/test_fog_cloud_overlay.gd.uid`).

---

## 10. Rollback Strategy

- **Git-Level Rollback:** Each C1.6 sub-milestone (`C1.6.1`–`C1.6.5`) lands as a small, verifiable unit. Reverting `fog_cloud_layer.gd`, `world_view.gd`, `save_manager.gd`, and `test_fog_cloud_overlay.gd` restores exact pre-C1.6 behavior with zero save-format incompatibility.
- **Runtime Kill-Switch:** Existing `WorldView.set_cloud_overlay_enabled(false)` and `debug_fog_disabled` toggle both `CloudSeaBase` and `FogCloudLayer` off without affecting `FogOfWar` or A2 `FogTileMapLayer`.

---

## 11. Known Warnings & Unresolved Questions

1. **Legacy `48×48` Cloud Assets:** Should `assets/fog/cloud_*.png` remain on disk during C1.6 for safe rollback, or be removed in a later cleanup pass? *(Plan recommends keeping them untouched in C1.6.)*
2. **Preset Selector:** `FogCloudLayer` currently exposes `DENSE`, `BALANCED`, and `LOOSE`. In C1.6, should `BALANCED` map directly to the validated `A_Medium` parameters (`420` sprites on `128×128`)? *(Recommended: yes, map `BALANCED` to `A_Medium`.)*

---

## 12. Acceptance Criteria per Sub-Milestone

- **C1.6.1 (Mask Engine):** `_sync_full_fog_mask_fast` + `_sync_dirty_fog_mask_fast` pass 100% byte-equivalence & zero-leak checks on `64×64`, `128×128`, `256×256`.
- **C1.6.2 (`CloudSeaBase`):** `CloudSeaBase` (`z=6`) renders V5 shader under `FogCloudLayer` (`z=7`) and above `FogTileMapLayer` (`z=5`), scales to `64×64` and `128×128`, and toggles with `debug_fog_disabled`.
- **C1.6.3 (Version A Foreground):** `main_cloud_01..03.png` render at `A_Medium` density with `TEXTURE_FILTER_NEAREST` and zero explored/visible tile overlap.
- **C1.6.4 (Day/Night):** `FogCloudLayer.modulate` RGB stays `(1, 1, 1)`, `test_day_night_phase1.gd` passes `42/42`, and Night/Dusk visuals match C1.5.5.
- **C1.6.5 (Lifecycle & Regression):** Cross-size Save/Load (`64×64 <-> 128×128`) rebinds `FogCloudLayer` + `CloudSeaBase` cleanly; `test_fog_rendering.gd`, `test_fog_debug_toggle.gd`, `test_fog_cloud_overlay.gd`, `test_day_night_phase1.gd`, `test_save_load.gd`, and `test_world_size_compatibility.gd` all pass with `0` failures.
