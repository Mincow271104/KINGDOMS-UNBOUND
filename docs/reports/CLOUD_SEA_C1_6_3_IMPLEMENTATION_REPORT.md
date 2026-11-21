# KINGDOMS UNBOUND — C1.6.3 Implementation Report
## Foreground Cloud Version A + A_Medium Density Integration

**Engine:** Godot 4.7 (`4.7-stable`, Windows)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Baseline HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Milestone:** C1.6.3 — Foreground Cloud Version A + `A_Medium` Density Integration

---

## 1. Pre-Implementation Git State

Recorded in `scratch/c1_6_3_baseline_git.txt` prior to edits:
- **HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Working Tree:** `413` pre-existing modified/untracked entries preserved untouched. No `git reset`, `git clean`, `git stash`, staging, commit, or push was performed.

---

## 2. Exact Files Added and Modified

### Modified
- `scripts/world/fog_cloud_layer.gd` — Replaced the legacy `48×48` sprite selection with the three approved Version A Main Cloud assets (`main_cloud_01..03.png`), added static opaque-footprint sampling (`stride = 6`) and cached foreground `ShaderMaterial`, and implemented the C1.5.5 `A_Medium` bank-cluster + bridge distribution inside `FogCloudLayer`'s chunked lifecycle (`CHUNK_SIZE = 8`, `FOOTPRINT_MARGIN = 6`).
- `scripts/test/test_fog_cloud_overlay.gd` — Updated and expanded to `49` assertions covering Version A dimensions, distribution across all 3 morphologies, non-legacy check, `A_Medium` (`BALANCED`) preset, seed determinism & variation, bounds safety, repeated `sync_full()` non-duplication, incremental cleanup, `debug_fog_disabled` toggle, and `z = 5/6/7/10` + `HUD` hierarchy.

### Added
- `docs/reports/CLOUD_SEA_C1_6_3_IMPLEMENTATION_REPORT.md`

---

## 3. Production Asset Metadata (Verified Directly)

| Asset | Dimensions | Mode & Alpha | Bytes | `.import` Present | Role |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `assets/fog/main_cloud_01_towering_cumulus.png` | `144×92` | `RGBA` (`A` present) | `1,452` | Yes | `TOWERING_CUMULUS` (`0`) |
| `assets/fog/main_cloud_02_sweeping_bank.png` | `160×84` | `RGBA` (`A` present) | `1,379` | Yes | `SWEEPING_BANK` (`1`) |
| `assets/fog/main_cloud_03_asymmetrical_cluster.png` | `136×88` | `RGBA` (`A` present) | `1,385` | Yes | `ASYMMETRICAL_CLUSTER` (`2`) |

Legacy `assets/fog/cloud_*.png` (`48×48`) assets remain untouched on disk.

---

## 4. Version A Implementation Details

- **Nearest-Neighbor & Shader:** `FogCloudLayer` uses `TEXTURE_FILTER_NEAREST` and `y_sort_enabled = true` at `z_index = 7`. All foreground `Sprite2D` nodes share a single statically cached `ShaderMaterial` (`tint_rgb = vec3(1.04, 1.08, 1.14)`, `mid_lift = 0.22`, `highlight_gain = 1.18`, `alpha_mult = 0.97`) matching the C1.5.5 prototype.
- **No Aspect Stretching:** Each sprite uses uniform scale (`sc` in `0.82..1.18`) preserving original pixel-art proportions.
- **Opaque Footprint Unexplored Check:** `_is_opaque_footprint_unexplored()` checks every `6×6` px opaque sample point against `FogOfWar.is_unexplored()`, guaranteeing zero overlap onto explored or visible territory.

---

## 5. A_Medium Density Configuration & Distribution

- **Bank + Bridge Targets (`BALANCED` = `A_Medium`):** Scaled by `(map_width * map_height) / (128.0 * 128.0)` -> **`82` bank centers** (`3–6` supports each) and **`68` bridge clouds** on `128×128`, with diversity-aware kind picking (`weights = [0.34, 0.36, 0.30]`, `prefer_bridge` favoring `ASYMMETRICAL_CLUSTER`) and neighbor scale differentiation (`>= 0.07`).
- **Measured `128×128` Distribution (`seed = 12345`, initial settlement reveal):**
  - **Total Active Foreground Instances:** **`440`** (consistent with C1.5.5 `~420–440` target at ~42–44% coverage)
  - **`main_cloud_01_towering_cumulus.png` (`0`):** `133` (`30.2%`)
  - **`main_cloud_02_sweeping_bank.png` (`1`):** `138` (`31.4%`)
  - **`main_cloud_03_asymmetrical_cluster.png` (`2`):** `169` (`38.4%`)

---

## 6. Deterministic Placement Verification

- Verified by `test_fog_cloud_overlay.gd`:
  - Two independent `FogCloudLayer` instances with identical seed (`424242`) and `FogOfWar` state produce **identical sorted positions** (`pos_a == pos_b`).
  - A different seed (`987654`) produces **valid, varied placements** (`pos_diff != pos_a`).
  - All active sprite center cells fall strictly within map bounds (`[0..mw-1, 0..mh-1]`).

---

## 7. Fog Synchronization and Lifecycle Behavior

- `_generate_world_chunk_candidates()` buckets deterministic candidates by `CHUNK_SIZE = 8`.
- `sync_full()` clears existing child sprites via `remove_child()` + `queue_free()`, updates the Fast Fog Mask, regenerates chunk candidates, and rebuilds all chunks.
- `update_dirty_cells(dirty_cells)` updates the incremental Fast Fog Mask and rebuilds only chunks within `FOOTPRINT_MARGIN = 6` cells of dirty tiles, matching `sync_full()` identically.
- Repeated `sync_full()` calls leave `get_child_count() == get_active_cloud_count()` (zero duplicate nodes).

---

## 8. Performance Measurements (`128×128`, `WorldView` Live Scene)

| Operation | Measured Time (ms) | Notes |
| :--- | :---: | :--- |
| **Initial / Full `sync_full()`** | **`286.327 ms`** | Reduced from `1123.790 ms` by switching opaque footprint stride from `2` to `6`. |
| **Repeated `sync_full()`** | **`354.126 ms`** | Full chunk teardown + rebuild. |
| **Incremental `_update_fog_visuals()`** *(4-tile pocket)* | **`4.403 ms`** | Includes `FogTileMapLayer`, incremental Fast Fog Mask, `ImageTexture.update()`, and dirty chunk rebuild. |

---

## 9. Test Results

| Suite | Assertions / Result | Exit Code | Notes |
| :--- | :--- | :---: | :--- |
| `scripts/test/test_fog_cloud_overlay.gd` | **PASS (`49` passed, `0` failed)** | **`0`** | Baseline exit warnings (`21 ObjectDB`, `8 resources`). |
| `scripts/test/test_fast_fog_mask_extended.gd` | **PASS (`78` passed, `0` failed)** | **`0`** | Zero leaks/warnings (`64×64`, `128×128`, `256×256`). |
| `scripts/test/test_fog_rendering.gd` | **PASS (`24` passed, `0` failed)** | **`0`** | Re-run after final edit; baseline exit warnings. |
| `scripts/test/test_fog_debug_toggle.gd` | **PASS (`15` passed, `0` failed)** | **`0`** | Re-run after final edit; baseline exit warnings. |

---

## 10. Visual Verification & Before/After Comparison

Captured in `scratch/c1_6_3_screenshots/` (`1280×720`, `128×128`, `1.5×` zoom, `12:00` Day, `seed = 12345`):
- `c1_6_3_settlement_day.png` — Large Version A cloud banks frame the settlement without obscuring terrain or `HUD`; `CloudSeaBase` V5 strata remain visible behind foreground banks.
- `c1_6_3_deep_cloud_sea_day.png` — Coherent horizontal cloud-bank formations with varied silhouettes, natural negative space, and no grid pattern or legacy `48×48` puff clutter.
- `c1_6_3_after_reveal_day.png` — Incremental scout reveal removes both foreground clouds and `CloudSeaBase` cleanly with zero stale sprites.
- `comp_c1_6_2_vs_c1_6_3.png` — Side-by-side comparison against C1.6.2 (`48×48` legacy) confirming clear hierarchy and reduced repetition.

---

## 11. Known Warnings and Limitations

- Existing `WorldView`-instantiating suites emit pre-existing Godot exit leak warnings (`21–35 ObjectDB`, `8 resources`) unrelated to C1.6.3.
- `FogCloudLayer.apply_day_night_tint()` still applies legacy RGB modulation (`C1.6.4` scope).

---

## 12. Scope Compliance

Strictly adhered to C1.6.3 restrictions:
- `CloudSeaBase` shader, textures, and `z_index = 6` unchanged.
- `FogCloudLayer.z_index` unchanged (`7`).
- Fast Fog Mask algorithm, `apply_day_night_tint()`, `DayNightModulate`, `save_manager.gd`, save schema, and legacy `48×48` assets on disk unchanged.

---

## 13. Remaining Work for C1.6.4

- Neutralize RGB modulation in `FogCloudLayer.apply_day_night_tint()` so `World/DayNightModulate` acts as the single Day/Night tint authority (preserving alpha `0.93–0.96`), and update `test_fog_cloud_overlay.gd` tint assertions accordingly.
- Subsequent milestone: C1.6.5 (Save/Load cross-dimension `FogOfWar` rebind guard + full regression).
