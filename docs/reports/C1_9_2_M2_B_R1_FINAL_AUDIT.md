# C1.9.2 — M2-B-R1 Final GPU Dirty-State & Idle Measurement Audit

**Project:** KINGDOMS UNBOUND  
**Engine:** Godot 4.7-stable  
**Milestone:** C1.9.2 — M2-B-R1 (Final GPU Dirty-State & Idle Measurement Audit)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Status:** AUDIT COMPLETE — M2-B Approved for Owner Sign-Off (M2-C not started)

---

## 1. Source Mutation API Audit Table

Audited `scripts/world/terrain_preview_field.gd` (lines 44–218 and 535–542):

| API | State-Changing Path | Failed / No-Op Path | Guarantees `_gpu_dirty = true` on GPU-Visible Change? |
|---|---|---|---|
| `configure()` | Resizes buffer/image/texture, recomputes phases, sets `_dirty_all = true`, `_gpu_dirty = true` (line 84). | N/A | **YES** |
| `clear_sources()` | When `not _sources.is_empty()`, sets `_gpu_dirty = true` (line 93), clears `_sources` and `_ordered_ids`. | When `_sources` is already empty, no state change; `_gpu_dirty` unchanged. | **YES** |
| `register_source()` | Calls `upsert_source(...)` for new non-empty `id` (line 110) -> `not _sources.has(id)` is `true` -> `_gpu_dirty = true` (line 158). | Empty `id` or existing `id` returns `false` early (lines 108–109); no state change. | **YES** |
| `upsert_source()` | Inserts new `id` or updates existing `id`; sets `_gpu_dirty = true` whenever `not _sources.has(id) or not _sources_equal(_sources[id], new_src)` (lines 157–158). | Empty `id` returns early (lines 123–124); identical parameters skip `_gpu_dirty = true`. | **YES** |
| `update_source()` | Reads existing `category`, resolves defaults, delegates to `upsert_source(...)` (lines 172–177) -> `_sources_equal()` detects any change in `cell`, `preview_radius_px`, `core_radius_px`, `dir`, or `oval_x` -> `_gpu_dirty = true`. | Missing `id` returns `false` early (lines 170–171); identical parameters leave `_gpu_dirty` unchanged. | **YES** |
| `remove_source()` | Erases from `_sources` and `_ordered_ids`, sets `_gpu_dirty = true` (lines 184–186), returns `true`. | Missing `id` returns `false` early (lines 182–183); no state change. | **YES** |

**Production Code Defect Check:** No defect found in `scripts/world/terrain_preview_field.gd`. Production code was **not modified**.

---

## 2. Exact Call-Chain Evidence

### 2.1 `register_source()` (`scripts/world/terrain_preview_field.gd:99-111`)
1. `register_source(id, category, cell, preview_radius_px, core_radius_px, dir, oval_x)` checks `if id.is_empty() or _sources.has(id): return false` (lines 108–109).
2. On a valid new `id`, it calls `upsert_source(id, category, cell, preview_radius_px, core_radius_px, dir, oval_x)` (line 110) and returns `true` (line 111).
3. Inside `upsert_source()` (`lines 114-159`), `not _sources.has(id)` evaluates to `true` (line 133 appends `id` to `_ordered_ids`; line 157 evaluates `not _sources.has(id)` -> `true`), setting `_gpu_dirty = true` (line 158) before writing `_sources[id] = new_src` (line 159).
4. On the next `TerrainPreviewRenderer.sync_if_needed()` (default `force = false`), `is_gpu_dirty()` is `true`, so the renderer packs `128x2` `RGBAF`, uploads to `ImageTexture`, marks `field.mark_gpu_synced()`, and sets `SubViewport.UPDATE_ONCE`.

### 2.2 `update_source()` (`scripts/world/terrain_preview_field.gd:162-178`)
1. `update_source(id, cell, preview_radius_px, core_radius_px, dir, oval_x)` checks `if not _sources.has(id): return false` (lines 170–171).
2. Reads `existing = _sources[id]` (line 172), preserves `existing["category"]` (line 173), resolves omitted `preview_radius_px` / `core_radius_px` / `oval_x` from `existing` (lines 174–176), and calls `upsert_source(id, cat, cell, p_rad, c_rad, dir, ox)` (line 177).
3. Inside `upsert_source()`, `_sources_equal(_sources[id], new_src)` (lines 535–542) compares:
   - `a["cell"] == b["cell"]`
   - `is_equal_approx(float(a["preview_radius_px"]), float(b["preview_radius_px"]))`
   - `is_equal_approx(float(a["core_radius_px"]), float(b["core_radius_px"]))`
   - `a["dir"] == b["dir"]`
   - `is_equal_approx(float(a["oval_x"]), float(b["oval_x"]))`
4. Any change in cell or any parameter sets `_gpu_dirty = true` (line 158), causing the next `TerrainPreviewRenderer.sync_if_needed()` (with `force = false`) to upload and render a new envelope pass.

---

## 3. Soldier Movement GPU Refresh Verification

In `scripts/test/test_terrain_preview_gpu_equiv.gd` (Section `1b`), the previous test passed `force = true` to `sync_if_needed(true)` during scenario `07_soldier_move`. A focused regression test was added using **default `sync_if_needed()` (`force = false`)**:

1. Registered Soldier `"s_move"` at `(24, 24)` via `register_source()` -> verified `field.is_gpu_dirty() == true`, `sync_if_needed()` returns `true`, `get_gpu_pass_count()` increments by `1`, and GPU readback confirms `(24, 24)` is revealed (`r8 < 128`) while `(96, 96)` is fogged (`r8 == 255`).
2. Executed failed mutations (`register_source` duplicate, `update_source` missing, `remove_source` missing) -> verified `not field.is_gpu_dirty()` and `not renderer.sync_if_needed()`.
3. Moved `"s_move"` to `(96, 96)` via `update_source("s_move", Vector2i(96, 96))` -> verified `field.is_gpu_dirty() == true`, `sync_if_needed()` returns `true`, and `get_gpu_pass_count()` increments by `1`.
4. Read back the GPU `ViewportTexture` after `frame_post_draw` -> verified `(96, 96)` is revealed (`r8 < 128`) and the old position `(24, 24)` is **no longer retained** (`r8 == 255 and g8 == 255`).
5. Verified parameter-only `update_source()` calls without changing cell (`dir` on `HUNTER_SCOUT`, `preview_radius_px`, `core_radius_px`, `oval_x`) and `remove_source()` with overlapping sources remaining each set `_gpu_dirty = true` and trigger `sync_if_needed()`.

---

## 4. Idle `UPDATE_DISABLED` & GPU Pass-Count Verification

Audited benchmark idle measurement in `scripts/test/test_terrain_preview_gpu_equiv.gd`:

- **Finding:** `RenderingServer.viewport_get_measured_render_time_gpu(sub_rid)` retains the last measured GPU timestamp when a `SubViewport` is `UPDATE_DISABLED` and skips rendering. Reporting that retained value as `idleGPU=...ms` was misleading.
- **Fix Applied to Test Harness:**
  - Removed the retained `idleGPU=...ms` readout from benchmark output; replaced with `idle=UPDATE_DISABLED/+0passes (gpu=unavailable)`.
  - Added explicit assertions over idle frames (both in Section 1 across 3 idle frames and in every benchmark configuration across 2 idle frames) verifying:
    - `sub_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED`
    - `renderer.get_gpu_pass_count()` increases by `+0`
    - `not renderer.is_update_pending()` and `not renderer.sync_if_needed()`

---

## 5. Tests Run & Assertion Counts

Executed after final edit to `scripts/test/test_terrain_preview_gpu_equiv.gd`:

1. **D3D12 Forward+ GPU Equivalence, Dirty-State & Benchmark Suite:**
   ```powershell
   & "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" -s "res://scripts/test/test_terrain_preview_gpu_equiv.gd"
   ```
   - **Result:** `exit=0`, **`PASS: test_terrain_preview_gpu_equiv.gd (60 assertions passed, 0 failed)`** (NVIDIA GeForce RTX 3050 Ti Laptop GPU).
2. **Headless CPU Field Regression Suite:**
   ```powershell
   & "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s "res://scripts/test/test_terrain_preview_field.gd"
   ```
   - **Result:** `exit=0`, **`PASS: test_terrain_preview_field.gd (21 assertions passed, 0 failed)`**.

---

## 6. Exact Files Modified

- **Modified (Test Harness Only):** `scripts/test/test_terrain_preview_gpu_equiv.gd`
- **Created (Audit Report):** `docs/reports/C1_9_2_M2_B_R1_FINAL_AUDIT.md`
- **Production Code Modified:** None (`scripts/world/terrain_preview_field.gd`, `scripts/world/terrain_preview_renderer.gd`, `shaders/fog/terrain_preview_envelope.gdshader`, `world_view.gd`, `fog_of_war.gd`, `fog_cloud_layer.gd`, `save_manager.gd`, scenes, and cloud shaders are untouched).

---

## 7. Final M2-B Recommendation

**APPROVE M2-B** for owner sign-off and proceed to **M2-C** (Cloud Composite & Production Wiring) upon owner authorization. All source-mutation dirty-state paths, Soldier movement GPU refreshes, and idle `UPDATE_DISABLED` / zero-pass guarantees are verified with 81 total passing assertions across both suites.
