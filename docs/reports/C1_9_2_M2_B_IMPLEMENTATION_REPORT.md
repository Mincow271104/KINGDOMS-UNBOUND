# C1.9.2 — M2-B Implementation Report: GPU Terrain Preview Renderer Foundation

**Project:** KINGDOMS UNBOUND  
**Engine:** Godot 4.7-stable  
**Milestone:** C1.9.2 — M2-B (GPU Terrain Preview Renderer Foundation)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Status:** COMPLETE — Ready for Owner Review (M2-C not started)

---

## 1. Executive Summary

M2-B implements the approved **Option B — GPU SubViewport Envelope Generation** foundation in isolation, without modifying production gameplay, scene, or cloud-composite layers:

- Extended `TerrainPreviewField` (`scripts/world/terrain_preview_field.gd`) with coalesced GPU dirty-state tracking (`_gpu_dirty`, `is_gpu_dirty()`, `mark_gpu_synced()`, `get_phase_offsets()`) and deterministic priority-ordered `128x2` `FORMAT_RGBAF` source packing (`pack_sources_into_rgba32f()`).
- Created `shaders/fog/terrain_preview_envelope.gdshader` to evaluate up to `128` preview sources per fragment via `texelFetch` on the `128x2` `RGBAF` source-data texture, including `smin_poly` blending and a `dist > 0.0001` guard to eliminate the `atan(0, 0)` center singularity.
- Created `TerrainPreviewRenderer` (`scripts/world/terrain_preview_renderer.gd`) owning the `SubViewport` (`disable_3d = true`, `UPDATE_DISABLED` when idle, coalesced `UPDATE_ONCE` on dirty updates), `ColorRect`, `ShaderMaterial`, `128x2` `FORMAT_RGBAF` `ImageTexture`, and `RenderingServer.frame_post_draw` reset handler.
- Verified **34/34** assertions in `scripts/test/test_terrain_preview_gpu_equiv.gd` (D3D12 12_0 Forward+) and **21/21** assertions in `scripts/test/test_terrain_preview_field.gd` (headless).

---

## 2. Git Baseline & Scope Compliance

- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Pre-existing dirty/untracked count:** `427` entries in `git status --short` (preserved untouched; no staging, committing, or pushing performed).
- **Files Modified (M2-B):**
  - `scripts/world/terrain_preview_field.gd`
- **Files Created (M2-B):**
  - `shaders/fog/terrain_preview_envelope.gdshader`
  - `scripts/world/terrain_preview_renderer.gd`
  - `scripts/test/test_terrain_preview_gpu_equiv.gd`
  - `docs/reports/C1_9_2_M2_B_IMPLEMENTATION_REPORT.md`
- **Explicitly Untouched (Out of Scope for M2-B):**
  - `scripts/world/world_view.gd`
  - `scripts/world/fog_of_war.gd`
  - `scripts/world/fog_cloud_layer.gd`
  - `scripts/persistence/save_manager.gd`
  - All existing `.tscn` scenes, cloud shaders, and art assets.

---

## 3. Architecture Overview (Option B)

1. `TerrainPreviewField` remains the CPU source registry, stable ID manager, dirty-state tracker, and CPU correctness reference.
2. When sources are added, updated, removed, or configured, `TerrainPreviewField` marks `_gpu_dirty = true`.
3. `TerrainPreviewRenderer.sync_if_needed()` coalesces any number of source mutations in a frame into a single `128x2` `FORMAT_RGBAF` upload and a single `SubViewport.UPDATE_ONCE` pass.
4. `RenderingServer.frame_post_draw` triggers `_on_frame_post_draw()`, which resets `render_target_update_mode = SubViewport.UPDATE_DISABLED` so idle frames execute zero envelope render passes.
5. `TerrainPreviewRenderer.get_envelope_texture()` exposes the generated `ViewportTexture` for future M2-C cloud composite integration.

---

## 4. `TerrainPreviewField` Updates

File: `scripts/world/terrain_preview_field.gd`

Added minimal GPU packing and dirty-state synchronization APIs while preserving all CPU reference behavior:
- `_gpu_dirty: bool` — marked dirty on `configure()`, `clear_sources()`, `upsert_source()`, and `remove_source()`.
- `is_gpu_dirty() -> bool` / `mark_gpu_synced() -> void` — enables coalesced GPU uploads.
- `get_phase_offsets() -> Vector2` — exposes deterministic phase offsets for the GPU shader.
- `pack_sources_into_rgba32f(img: Image, max_slots: int = 128) -> Dictionary` — packs sources in deterministic priority order (`TOWN_HALL -> HUNTER_SCOUT -> SOLDIER`) into a `128x2` `FORMAT_RGBAF` `Image`, zero-fills unused slots, and emits `push_warning` on overflow beyond `max_slots` (`128`).

---

## 5. GPU Envelope Shader

File: `shaders/fog/terrain_preview_envelope.gdshader`

- `MAX_SOURCE_SLOTS = 128`.
- Reads source parameters from `source_data_tex` (`128x2` `FORMAT_RGBAF`) via `texelFetch` on Row `0` and Row `1`.
- Evaluates `smin_poly` smooth-minimum envelope blending across active slots, Day/Night neutral.
- Guards `if (dist > 0.0001)` before directional angle evaluation to eliminate the `atan(0, 0)` center singularity, reducing `1x` peak `G` channel discrepancy from `4/255` to `1/255`.

---

## 6. `TerrainPreviewRenderer` Lifecycle & Coalescing

File: `scripts/world/terrain_preview_renderer.gd` (`class_name TerrainPreviewRenderer extends Node`)

- `MAX_SOURCE_SLOTS = 128`.
- Owns `SubViewport`, `ColorRect`, `ShaderMaterial`, and the `128x2` `FORMAT_RGBAF` `ImageTexture`.
- Public API:
  - `configure(...)`
  - `set_resolution_scale(...)`
  - `request_update()`
  - `sync_if_needed(...)`
  - `get_envelope_texture()`
  - `get_subviewport()`
  - `get_source_data_texture()`
  - `is_update_pending()`
  - `get_gpu_pass_count()`
  - `get_last_stats()`
  - `get_memory_bytes()`
  - `cleanup()`
- `_on_frame_post_draw()` listens to `RenderingServer.frame_post_draw` and explicitly resets `render_target_update_mode = SubViewport.UPDATE_DISABLED` after an `UPDATE_ONCE` pass (required in Godot 4.7 because `UPDATE_ONCE` does not automatically mutate the GDScript property back to `UPDATE_DISABLED`).

---

## 7. CPU vs. GPU Equivalence Verification

Command executed after final edits:
```powershell
& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" -s "res://scripts/test/test_terrain_preview_gpu_equiv.gd"
```
Result: `exit=0`, **`PASS: test_terrain_preview_gpu_equiv.gd (34 assertions passed, 0 failed)`** (D3D12 12_0 Forward+, NVIDIA GeForce RTX 3050 Ti Laptop GPU).

### 7.1 `1x` Resolution Equivalence (Tolerance `<= 4/255`)

| Scenario | `max_R` | `max_G` | `mean_R` | `mean_G` | Status |
|---|---:|---:|---:|---:|---|
| `01_empty` | 0 | 0 | 0.000 | 0.000 | PASS |
| `02_one_town_hall` | 1 | 1 | 0.010 | 0.003 | PASS |
| `03_three_nearby` | 1 | 1 | 0.011 | 0.004 | PASS |
| `04_separated` | 1 | 1 | 0.013 | 0.007 | PASS |
| `05_eight_overlapping` | 1 | 1 | 0.014 | 0.007 | PASS |
| `06_hunter_directional` | 1 | 1 | 0.015 | 0.007 | PASS |
| `07_soldier_move` | 1 | 1 | 0.015 | 0.009 | PASS |
| `08_multi_simultaneous` | 1 | 1 | 0.016 | 0.009 | PASS |
| `09_remove_overlapping` | 1 | 1 | 0.015 | 0.009 | PASS |
| `10_map_edge` | 1 | 1 | 0.017 | 0.009 | PASS |

### 7.2 `2x` Resolution Equivalence (Tolerance `<= 2/255`)

| Scenario | `max_R` | `max_G` | `mean_R` | `mean_G` | Status |
|---|---:|---:|---:|---:|---|
| `01_empty` | 0 | 0 | 0.000 | 0.000 | PASS |
| `02_one_town_hall` | 1 | 1 | 0.011 | 0.003 | PASS |
| `03_three_nearby` | 1 | 1 | 0.011 | 0.004 | PASS |
| `04_separated` | 1 | 1 | 0.014 | 0.006 | PASS |
| `05_eight_overlapping` | 1 | 1 | 0.014 | 0.007 | PASS |
| `06_hunter_directional` | 1 | 1 | 0.015 | 0.007 | PASS |
| `07_soldier_move` | 1 | 1 | 0.017 | 0.008 | PASS |
| `08_multi_simultaneous` | 1 | 1 | 0.017 | 0.007 | PASS |
| `09_remove_overlapping` | 1 | 1 | 0.017 | 0.008 | PASS |
| `10_map_edge` | 1 | 1 | 0.018 | 0.008 | PASS |

Additional verified assertions in `test_terrain_preview_gpu_equiv.gd`:
- Lifecycle & `UPDATE_ONCE` -> `UPDATE_DISABLED` reset on `frame_post_draw`.
- Multi-mutation coalescing into a single GPU pass.
- `128`-slot capacity and `130`-source overflow priority ordering (`TOWN_HALL -> HUNTER_SCOUT -> SOLDIER`).
- `cleanup()` frees the `SubViewport` and clears the `ViewportTexture` reference.

---

## 8. D3D12 Forward+ Performance & Memory Benchmarks

Observed from `test_terrain_preview_gpu_equiv.gd` (D3D12 12_0 Forward+, NVIDIA GeForce RTX 3050 Ti Laptop GPU):

| Resolution | Sources | Memory | Pack (min/max ms) | Upload (min/max ms) | SubViewport GPU (min/max ms) | Idle GPU (ms)* |
|---|---:|---:|---:|---:|---:|---:|
| `1x` (`128x128`) | 1 | 72 KB | 0.031 / 0.036 | 0.015 / 0.024 | 0.012 / 0.016 | 0.012 |
| `1x` (`128x128`) | 8 | 72 KB | 0.036 / 0.061 | 0.015 / 0.034 | 0.017 / 0.018 | 0.018 |
| `1x` (`128x128`) | 32 | 72 KB | 0.070 / 0.090 | 0.015 / 0.016 | 0.038 / 0.038 | 0.038 |
| `1x` (`128x128`) | 64 | 72 KB | 0.143 / 0.161 | 0.016 / 0.022 | 0.061 / 0.066 | 0.066 |
| `1x` (`128x128`) | 128 | 72 KB | 0.216 / 0.251 | 0.014 / 0.022 | 0.120 / 0.121 | 0.121 |
| `2x` (`256x256`) | 1 | 264 KB | 0.023 / 0.024 | 0.012 / 0.013 | 0.016 / 0.121 | 0.015 |
| `2x` (`256x256`) | 8 | 264 KB | 0.048 / 0.051 | 0.019 / 0.022 | 0.032 / 0.032 | 0.031 |
| `2x` (`256x256`) | 32 | 264 KB | 0.079 / 0.106 | 0.017 / 0.021 | 0.090 / 0.091 | 0.089 |
| `2x` (`256x256`) | 64 | 264 KB | 0.112 / 0.151 | 0.013 / 0.020 | 0.165 / 0.167 | 0.166 |
| `2x` (`256x256`) | 128 | 264 KB | 0.189 / 0.229 | 0.014 / 0.017 | 0.320 / 0.321 | 0.320 |

**Memory Breakdown:**
- `128x2` `FORMAT_RGBAF`: `128 * 2 * 16 = 4,096 B` CPU `Image` + `4,096 B` VRAM `ImageTexture` (`8 KB` total).
- `SubViewport` `RGBA8`: `64 KB` at `128x128` (`1x` -> `72 KB` total) and `256 KB` at `256x256` (`2x` -> `264 KB` total).

\* **Idle GPU Measurement Note:** `RenderingServer.viewport_get_measured_render_time_gpu(sub_rid)` retains the last measured GPU timestamp when a `SubViewport` is `UPDATE_DISABLED` and skips rendering; `sub_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED` confirms zero active envelope render passes occur on idle frames.

---

## 9. Regression Verification

Command executed after final edits:
```powershell
& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless -s "res://scripts/test/test_terrain_preview_field.gd"
```
Result: `exit=0`, **`PASS: test_terrain_preview_field.gd (21 assertions passed, 0 failed)`**.

---

## 10. Known Limitations & Notes for M2-C

- `MAX_SOURCE_SLOTS` is capped at `128` active preview sources, prioritized deterministically as `TOWN_HALL -> HUNTER_SCOUT -> SOLDIER`.
- Godot 4.7 `SubViewport.UPDATE_ONCE` requires explicit reset to `SubViewport.UPDATE_DISABLED` via `RenderingServer.frame_post_draw`.
- Cloud composite shader integration and `WorldView` / `FogCloudLayer` wiring are intentionally deferred to M2-C.

---

## 11. Next Gate & Handoff Status

- **Current Milestone Status:** M2-B complete and verified.
- **Gate:** Stopping here for Owner Review before beginning **M2-C** (Cloud Composite & Production Wiring).
