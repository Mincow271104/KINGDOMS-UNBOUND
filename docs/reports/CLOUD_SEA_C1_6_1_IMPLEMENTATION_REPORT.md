# KINGDOMS UNBOUND — C1.6.1 Implementation Report
## Fast Fog Mask Engine + Safe Asset Promotion

**Engine:** Godot 4.7 (`4.7-stable`, Windows)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Baseline HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Milestone:** C1.6.1 — Fast Fog Mask Engine + Safe Asset Promotion (Isolated from `CloudSeaBase` shader & visual changes)

---

## 1. Pre-Implementation Git State

Recorded in `scratch/c1_6_1_baseline_git.txt` prior to any edits:
- **HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Working Tree:** `409` pre-existing modified/untracked entries preserved untouched. No `git reset`, `git clean`, `git stash`, staging, commit, or push was performed.

---

## 2. Files Added and Modified

### Modified
- `scripts/world/fog_cloud_layer.gd` — Added the 2-pass `PackedByteArray` Fast Fog Mask engine (`_sync_full_fog_mask_fast()`, `_sync_dirty_fog_mask_fast()`, `_upload_fog_mask()`, `get_fog_mask_image()`, `get_fog_mask_texture()`), retained the reference implementation (`_compute_cell_mask_value_ref()`, `_sync_full_fog_mask_ref()`) for ongoing equivalence verification, and wired mask updates into `sync_full()` and `update_dirty_cells()`.

### Added
- `scripts/test/test_fast_fog_mask_extended.gd` — Official extended regression & equivalence suite testing `FogCloudLayer` directly across `64×64`, `128×128`, and `256×256`.
- `assets/fog/cloud_sea_base_v4_512.png`
- `assets/fog/cloud_sea_base_v5_wisps_512.png`
- `assets/fog/main_cloud_01_towering_cumulus.png`
- `assets/fog/main_cloud_02_sweeping_bank.png`
- `assets/fog/main_cloud_03_asymmetrical_cluster.png`
- `docs/reports/CLOUD_SEA_C1_6_1_IMPLEMENTATION_REPORT.md`

---

## 3. Algorithm Implementation Details

1. **2-Pass Manhattan (L1) Distance Transform (`_sync_full_fog_mask_fast`):**
   - Initializes a `PackedByteArray` of size `map_width * map_height` (`4` for `UNEXPLORED`, `0` for `EXPLORED` / `VISIBLE`).
   - Pass 1 sweeps Top-Left to Bottom-Right (`min(d, left + 1, up + 1)`).
   - Pass 2 sweeps Bottom-Right to Top-Left (`min(d, right + 1, down + 1)`).
   - Maps clamped distance `[0..4]` through `_ensure_mask_lut()` (`[0, 0, 107, 198, 255]`), initialized via `Image.set_pixel()` so byte truncation for `0.42` (`107`) and `0.78` (`198`) matches the reference `Image` output byte-for-byte.
   - Constructs an `Image.FORMAT_RGBA8` image via `Image.create_from_data()` and uploads via `ImageTexture.update()` (recreating only when dimensions change).
2. **Incremental Dirty-Rect Transform (`_sync_dirty_fog_mask_fast`):**
   - Computes a clamped bounding box around `dirty_cells` padded by `±3` for the write region and `±6` (`write ± 3`) for the read margin so L1 boundary distances `<= 3` are exact.
   - Falls back to `_sync_full_fog_mask_fast()` if `_fog_mask_img` is null or mismatched in size.

---

## 4. Asset Source, Destination, Dimensions, and Integrity

All 5 assets were copied without overwriting any existing `assets/fog/cloud_*.png` legacy files and verified via SHA-256 and `PIL.Image`:

| Asset | Verified Source | Destination | Size (px) & Mode | Bytes | SHA-256 |
| :--- | :--- | :--- | :---: | :---: | :--- |
| `cloud_sea_base_v4_512.png` | `scratch/c1_5_5_refined_hybrid/assets/` | `assets/fog/cloud_sea_base_v4_512.png` | `512×512` RGBA | `4,525` | `D079D90A...073A724E` |
| `cloud_sea_base_v5_wisps_512.png` | `scratch/c1_5_5_refined_hybrid/assets/` | `assets/fog/cloud_sea_base_v5_wisps_512.png` | `512×512` RGBA | `4,439` | `BA3B880D...8502DEC` |
| `main_cloud_01_towering_cumulus.png` | `scratch/c1_1_refined/` | `assets/fog/main_cloud_01_towering_cumulus.png` | `144×92` RGBA | `1,452` | `51B62307...91C77007` |
| `main_cloud_02_sweeping_bank.png` | `scratch/c1_1_refined/` | `assets/fog/main_cloud_02_sweeping_bank.png` | `160×84` RGBA | `1,379` | `2EB36C24...735FD53A` |
| `main_cloud_03_asymmetrical_cluster.png` | `scratch/c1_1_refined/` | `assets/fog/main_cloud_03_asymmetrical_cluster.png` | `136×88` RGBA | `1,385` | `AF5E1AC4...86DE0BB1` |

---

## 5. Extended Test Results (`test_fast_fog_mask_extended.gd`)

Executed `res://scripts/test/test_fast_fog_mask_extended.gd` in headless Godot 4.7:
- **Result:** **`PASS: test_fast_fog_mask_extended.gd (78 assertions passed, 0 failed)`**, exit code `0`.
- **Coverage across `64×64`, `128×128`, `256×256`:** Empty exploration, boundary-adjacent reveals (corners + edge), disconnected explored regions, observer degradation (`update_observers([], 0)`), overlapping scout pockets, repeated reveals, `update_dirty_cells()` vs full sync (`inc_matches_full == true`), simulated Save/Load rebuild, fully explored map, and zero explored/visible tile leaks.
- **CPU Memory Footprint (`dist` + `rgba` buffers):** `20 KB` (`64×64`), `80 KB` (`128×128`), `320 KB` (`256×256`).

---

## 6. Performance Comparison

| Map Size | Reference `7×7` (ms) | Fast Full Avg (ms) | Fast Full Median (ms) | Fast Full P95 / Worst (ms) | `update_dirty_cells` Total* (ms) | `inc_matches_full` |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`64×64`** | `116.805` | **`1.981`** | **`1.929`** | `2.293` / `2.293` | `1.361` | **`true`** |
| **`128×128`** | `595.539` | **`8.421`** | **`8.377`** | `10.203` / `10.203` | `1.639` | **`true`** |
| **`256×256`** | `2468.302` | **`35.762`** | **`36.252`** | `40.824` / `40.824` | `1.461` | **`true`** |

*\*`update_dirty_cells()` timing includes the incremental mask transform, `ImageTexture.update()`, and existing `FogCloudLayer` chunk `Sprite2D` rebuilds.*

**Baseline Comparison:** Matches the C1.5.5 (`8.981 ms` avg) and C1.6 audit (`8.49 ms` avg) `128×128` results on the same Windows Godot 4.7 headless environment (`8.421 ms` avg, **70.7×** speedup over `595.539 ms`).

---

## 7. Regression Test Results

| Suite | Result | Notes |
| :--- | :--- | :--- |
| `scripts/test/test_fast_fog_mask_extended.gd` | **PASS (78/78, 0 failed)** | Exit code `0`, zero leaks/warnings. |
| `scripts/test/test_fog_cloud_overlay.gd` | **PASS (all assertions)** | Exit code `0`; logs baseline exit leak warnings (`21 ObjectDB`, `8 resources`). |
| `scripts/test/test_fog_rendering.gd` | **PASS (24/24, 0 failed)** | Exit code `0`; logs baseline exit leak warnings (`35 ObjectDB`, `8 resources`). |
| `scripts/test/test_fog_debug_toggle.gd` | **PASS (15/15, 0 failed)** | Exit code `0`; logs baseline exit leak warnings (`21 ObjectDB`, `8 resources`). |

---

## 8. Known Warnings

- Existing `WorldView`-instantiating suites (`test_fog_cloud_overlay.gd`, `test_fog_rendering.gd`, `test_fog_debug_toggle.gd`) emit pre-existing Godot exit warnings (`21–35 ObjectDB instances leaked`, `8 resources still in use`) unrelated to C1.6.1.
- `test_fast_fog_mask_extended.gd` exited cleanly with `0` ObjectDB/resource leak warnings.

---

## 9. Scope Compliance

Strictly adhered to C1.6.1 boundaries:
- No `CloudSeaBase` node or V5 shader added.
- `FogCloudLayer.z_index` left at `6`.
- Foreground textures and `DensityPreset` behavior unchanged (`48×48` legacy assets untouched).
- `apply_day_night_tint()`, `world_view.gd`, `save_manager.gd`, and save schema untouched.

---

## 10. Remaining Work for C1.6.2

- Mount `CloudSeaBase` (`Polygon2D` with V5 MultiScale shader using `get_fog_mask_texture()`) at `z_index = 6` and move `FogCloudLayer.z_index` to `7` (updating `test_fog_cloud_overlay.gd` accordingly).
- Subsequent milestones: C1.6.3 (Version A foreground + `A_Medium`), C1.6.4 (Day/Night single-authority tint fix), C1.6.5 (Save/Load cross-dimension rebind guard + full regression).
