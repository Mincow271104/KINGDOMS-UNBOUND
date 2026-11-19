# KINGDOMS UNBOUND — C1.9.2 M2-C3-R1 Implementation & Final Acceptance Report

**Milestone:** C1.9.2 M2-C3-R1 — Production Remediation, Town Hall Upgrade Synchronization & Final Acceptance  
**Engine:** Godot 4.7-stable (`E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe`)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Final Verdict:** **PASS**

---

## 1. Executive Summary

M2-C3-R1 remediates the blocking Town Hall upgrade synchronization defect identified in the M2-C3 Final Acceptance Audit, aligns Hunter/Scout preview qualification with `FogOfWar` / `refresh_world_vision()`, updates legacy fog unit tests (`test_fog_rendering.gd` and `test_fog_cloud_overlay.gd`) to explicitly validate both Composite mode (default) and Legacy mode, and completes the full 17-suite regression matrix (6 D3D12 + 11 headless) alongside live visual verification (`seed = 12345`, `1280x720`, D3D12).

All 17 automated test suites pass with **0 failures** and exit code **0** after the final edits. Live visual inspection confirms that Town Hall L1 (`13` cells), L2 (`18` cells), and L3 (`24` cells) expand the cloud opening proportionally (`350.0 / 200.0 px` → `484.6 / 276.9 px` → `646.2 / 369.2 px`) with `+1` GPU pass per upgrade and **0** rectangular FogOfWar silhouette leaks.

---

## 2. Files Created or Modified

| File | Change Summary |
|---|---|
| `scripts/world/world_view.gd` | Added `_resolve_active_townhall_info()` (`L4491–L4507`); scaled Town Hall `TerrainPreviewField` radii deterministically in `sync_gameplay_terrain_preview_sources()` (`L4521–L4537`); triggered `sync_gameplay_terrain_preview_sources()` in `complete_upgrade()` when `b_type == "townhall"` (`L3169`); aligned Hunter/Scout qualification in `sync_gameplay_terrain_preview_sources()` (`L4547`) and `_sync_hunter_preview_sources_if_moved()` (`L4610`) to `can_scout_beyond_territory == true`. |
| `scripts/entities/citizen_controller.gd` | Declared `var can_scout_beyond_territory: bool = false` (`L44`) so `CitizenController` explicitly carries the scouting capability flag checked by `refresh_world_vision()` and `sync_gameplay_terrain_preview_sources()`. |
| `scripts/test/test_c192_m2_c3_production_cloud.gd` | Added Town Hall L1 → L2 → L3 upgrade synchronization assertions (radii scaling, `+1` GPU pass per upgrade, idle zero-pass stability, destruction/restoration preservation) and ordinary Hunter vs. qualified Scout (`can_scout_beyond_territory == true`) assertions (50 assertions total). |
| `scripts/test/test_fog_rendering.gd` | Validated Composite mode default (no duplicate fog) and explicitly switched to Legacy mode via `set_cloud_sea_composite_isolated_mode(false)` + `_sync_full_fog_layer()` for legacy `FogTileMapLayer` assertions (26 assertions total). |
| `scripts/test/test_fog_cloud_overlay.gd` | Validated Composite mode default + `set_debug_fog_disabled(true/false)` and switched to Legacy mode for `fog_mask` / `CloudSeaBase` shader assertions before restoring Composite mode (66 assertions total). |
| `docs/reports/C1_9_2_M2_C3_R1_IMPLEMENTATION_REPORT.md` | This final implementation & acceptance report. |

---

## 3. Town Hall Upgrade Synchronization (Blocking Fix)

### 3.1 Root Cause
Previously, `sync_gameplay_terrain_preview_sources()` registered `"townhall_main"` with fixed Level 1 constants (`TOWN_HALL_PREVIEW_RADIUS_PX = 350.0`, `TOWN_HALL_CORE_RADIUS_PX = 200.0`) and `complete_upgrade()` did not re-sync `TerrainPreviewField` when a Town Hall upgraded.

### 3.2 Deterministic Scaling & Isometric Geometry Proof
`WorldView._resolve_active_townhall_info()` (`scripts/world/world_view.gd:4491-4507`) reads the active non-destroyed Town Hall's `upgrade_level` (clamped to `1..EconomyConfig.MAX_BUILDING_LEVEL`) and queries `EconomyConfig.get_territory_radius(th_lvl)`:

- `rad_scale = float(cur_rad) / float(EconomyConfig.get_territory_radius(1))`
- `preview_radius_px = TOWN_HALL_PREVIEW_RADIUS_PX * rad_scale`
- `core_radius_px = TOWN_HALL_CORE_RADIUS_PX * rad_scale`

With `IsoMath.HALF_WIDTH = 16.0`, `IsoMath.HALF_HEIGHT = 8.0`, and `TerrainPreviewField.DEFAULT_OVAL_X = 1.65`, a Manhattan territory radius `R` spans `x ∈ [-16R, +16R]`, `y ∈ [-8R, +8R]`, whose corners lie at normalized elliptical distance `d_iso_corner = R * sqrt((16 / 1.65)^2 + 8^2) = 12.571 * R`:

| Town Hall Level | Territory Radius (`EconomyConfig`) | Territory Cells | `d_iso_corner` (px) | `core_radius_px` (px) | Core Margin (px) | `preview_radius_px` (px) |
|---|---:|---:|---:|---:|---:|---:|
| Level 1 | 13 | 365 | 163.4 | 200.0 | +36.6 | 350.0 |
| Level 2 | 18 | 685 | 226.3 | 276.9 | +50.6 | 484.6 |
| Level 3 | 24 | 1201 | 301.7 | 369.2 | +67.5 | 646.2 |

### 3.3 Upgrade Trigger & Idle Stability
- `WorldView.complete_upgrade()` (`scripts/world/world_view.gd:3169`) invokes `sync_gameplay_terrain_preview_sources()` when `b_type == "townhall"`.
- In `test_c192_m2_c3_production_cloud.gd` and the live D3D12 upgrade audit (`audit_m2_c3_visual_and_upgrade.gd`), L1 → L2 and L2 → L3 each trigger exactly **+1** GPU envelope pass (`gpu_passes`: `2` → `3` → `4`), while idle frames trigger **0** redundant GPU passes.
- Town Hall destruction removes `"townhall_main"` cleanly; restoration re-registers `"townhall_main"` with the preserved upgraded radius.

---

## 4. Hunter / Scout Qualification Alignment

Both `sync_gameplay_terrain_preview_sources()` (`scripts/world/world_view.gd:4547`) and `_sync_hunter_preview_sources_if_moved()` (`scripts/world/world_view.gd:4610`) now qualify citizens strictly via `cit.get("can_scout_beyond_territory") == true`, matching `refresh_world_vision()`. Ordinary `role == "hunter"` citizens without `can_scout_beyond_territory == true` no longer create `HUNTER_SCOUT` preview sources, while qualified scouts (`can_scout_beyond_territory == true`) do. `CitizenController` (`scripts/entities/citizen_controller.gd:44`) explicitly declares `var can_scout_beyond_territory: bool = false`.

---

## 5. Legacy Fog Test Alignment

- **`scripts/test/test_fog_rendering.gd`** (`26 passed, 0 failed`): Verifies Composite mode is active by default without duplicate fog, then switches to Legacy mode via `set_cloud_sea_composite_isolated_mode(false)` and calls `_sync_full_fog_layer()` to validate legacy `FogTileMapLayer` visibility/explored state rendering.
- **`scripts/test/test_fog_cloud_overlay.gd`** (`66 passed, 0 failed`): Verifies Composite mode default and `set_debug_fog_disabled(true/false)` behavior, switches to Legacy mode to validate `fog_mask` / `CloudSeaBase` shader behavior, and restores Composite mode.

---

## 6. Complete Automated Test Matrix (Post-Remediation)

All 17 suites were executed **after the final edits** and exited with code **0**.

### 6.1 D3D12 / Rendering Suites (6 / 6 Passed)

| Suite | Result | Exit Code |
|---|---|---:|
| `res://scripts/test/test_c192_m2_c3_production_cloud.gd` | `PASS: test_c192_m2_c3_production_cloud.gd (50 assertions passed, 0 failed)` | 0 |
| `res://scripts/test/test_cloud_sea_composite.gd` | `PASS: test_cloud_sea_composite.gd (24 assertions passed, 0 failed)` | 0 |
| `res://scripts/test/test_cloud_sea_fog_state_composition.gd` | `PASS: test_cloud_sea_fog_state_composition.gd (19 assertions passed, 0 failed)` | 0 |
| `res://scripts/test/test_cloud_sea_visibility_safety.gd` | `PASS: test_cloud_sea_visibility_safety.gd (11 assertions passed, 0 failed)` | 0 |
| `res://scripts/test/test_terrain_preview_gpu_equiv.gd` | `PASS: test_terrain_preview_gpu_equiv.gd (60 assertions passed, 0 failed)` | 0 |
| `res://scripts/test/test_world_view_preview_lifecycle.gd` | `PASS: test_world_view_preview_lifecycle.gd (16 assertions passed, 0 failed)` | 0 |

### 6.2 Headless Suites (11 / 11 Passed)

| Suite | Result | Exit Code |
|---|---|---:|
| `res://scripts/test/test_terrain_preview_field.gd` | `PASS: test_terrain_preview_field.gd (21 assertions passed, 0 failed)` | 0 |
| `res://scripts/test/test_fog_of_war_reconnaissance.gd` | `Passed: 127 \| Failed: 0` | 0 |
| `res://scripts/test/test_fog_rendering.gd` | `PHASE 3 FOG RENDERING RESULTS: 26 passed, 0 failed` | 0 |
| `res://scripts/test/test_fog_debug_toggle.gd` | `PHASE 5 FOG DEBUG TOGGLE RESULTS: 15 passed, 0 failed` | 0 |
| `res://scripts/test/test_fog_cloud_overlay.gd` | `PASS: test_fog_cloud_overlay.gd (66 assertions passed, 0 failed)` | 0 |
| `res://scripts/test/test_save_load.gd` | `Assertions Passed: 182 \| Failed: 0` (`ALL PHASE 8 PERSISTENCE TESTS PASSED!`) | 0 |
| `res://scripts/test/test_repeated_save_load_scene_cleanup.gd` | `RISK-005 SUITE: ALL 38 SCENARIO CHECKS PASSED! (0 Failures)` | 0 |
| `res://scripts/test/test_day_night_phase1.gd` | `TEST SUITE COMPLETE: 42 passed, 0 failed` | 0 |
| `res://scripts/test/test_hunter_system.gd` | `[test_hunter_system] Passed: 2028 \| Failed: 0` | 0 |
| `res://scripts/test/test_tactical_military.gd` | `All Package 1W Tactical Military Tests PASSED! (419 assertions)` | 0 |
| `res://scripts/test/test_all_scripts_load.gd` | `GAP-006 RESULTS: 231 / 231 Scripts Compiled Successfully` | 0 |

---

## 7. Save/Load, Lifecycle & Visibility Safety

- Save/Load after Town Hall upgrade, repeated load cleanup (`test_repeated_save_load_scene_cleanup.gd`, 38 scenario checks), and lifecycle cleanup (`test_world_view_preview_lifecycle.gd`, 16 assertions) all pass with zero duplicate nodes or preview sources.
- `FogOfWar` remains the sole gameplay discovery and entity visibility authority (`test_cloud_sea_visibility_safety.gd`, 11 assertions; `test_fog_of_war_reconnaissance.gd`, 127 assertions).

---

## 8. Live Visual Verification (D3D12, `seed = 12345`, `1280x720`)

Executed live D3D12 visual verification via `audit_m2_c3_visual_and_upgrade.gd` (screenshots stored in conversation scratch directory `m2_c3_audit/`):

- **L1 (`08_upgrade_l1_zoom_100.png`, `09_upgrade_l1_zoom_075.png`):** `365` territory cells, `350.0 / 200.0 px` preview/core radii, `gpu_passes=2`. Clean organic cloud framing around the settlement.
- **L2 (`10_upgrade_l2_zoom_100.png`, `11_upgrade_l2_zoom_075.png`, `14_upgrade_l2_debug3_alpha.png`):** `685` territory cells, `484.6 / 276.9 px` preview/core radii, `gpu_passes=3`. Cloud opening expands proportionally with zero rectangular cutout.
- **L3 (`15_upgrade_l3_zoom_100.png`, `16_upgrade_l3_zoom_075.png`):** `1201` territory cells, `646.2 / 369.2 px` preview/core radii, `gpu_passes=4`. Expanded perimeter remains organically framed by volumetric cloud edges.

---

## 9. Git Status & Hygiene

- Branch verified: `feature/package-3a-outpost-garrison-reinforcement`
- Base HEAD preserved: `e1d379b93a48db018c7b412b896caa9592f6980c`
- `git diff --check` on all modified files exited `0` (clean whitespace).
- No commits, pushes, staging, resets, or destructive Git operations were performed.

---

## 10. Final Acceptance Verdict

**PASS** — Blocking Town Hall upgrade synchronization is fixed and verified mathematically, programmatically, and visually; Hunter/Scout qualification matches `refresh_world_vision()`; legacy fog tests validate both Composite and Legacy modes; and all 17/17 test suites (6 D3D12 + 11 headless) pass with 0 failures.
