# KINGDOMS UNBOUND — C1.9.2 M2-C3 Final Acceptance Audit

**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Engine:** Godot 4.7-stable (D3D12 Forward+ — NVIDIA GeForce RTX 3050 Ti Laptop GPU)  
**Audit Date:** 2026-11-16  
**Final Verdict:** **FAIL** *(Blocking defect confirmed in Section 2A: Town Hall upgrade territory-preview mismatch; plus non-blocking findings in Section 4 Hunter qualification and 2 legacy fog test suites in Section 7.)*

---

## 1. Visual Acceptance (`seed = 12345`, `1280x720`, D3D12 Forward+)

Audit screenshots saved to `C:\Users\HP\.gemini\antigravity\brain\14962f4b-f0f0-45b2-a6cb-329cefe5b824\scratch\m2_c3_audit\`:

| Image | File Path | Findings |
| --- | --- | --- |
| Day `0.75x` | `...\m2_c3_audit\01_day_zoom_075.png` | Town Hall at `(63, 62)` is centered in the organic cloud opening; balanced opening size; coastline, forest, and settlement buildings framed naturally; zero dark overlay; zero diamond/rectangular boundary; zero double fog. |
| Day `1.0x` | `...\m2_c3_audit\02_day_zoom_100.png` | Same clean framing at `1.0x`; world-space cloud textures match `0.75x` scale cleanly. |
| Day `1.5x` | `...\m2_c3_audit\03_day_zoom_150.png` | Cloud textures remain locked to world coordinates without screen-space swimming or distortion. |
| Dawn `1.0x` (`5.5h`) | `...\m2_c3_audit\04_dawn_zoom_100.png` | Warm dawn tint applied uniformly to terrain and cloud sea via single `World/DayNightModulate`. |
| Dusk `1.0x` (`18.5h`) | `...\m2_c3_audit\05_dusk_zoom_100.png` | Warm amber dusk tint applied uniformly with no compounded RGB modulation. |
| Night `1.0x` (`23.0h`) | `...\m2_c3_audit\06_night_zoom_100.png` | Cool night tint applied uniformly across terrain and cloud sea. |
| `EXPLORED_NOT_VISIBLE` outside preview | `...\m2_c3_audit\07_explored_not_visible_outside_preview.png` | Explored patch around `(24, 24)` renders as natural terrain with **zero dark overlay** (`a = 0.00`), framed cleanly by surrounding `UNEXPLORED` cloud sea. |

- **Initial Level 1 Visual Assessment:** **PASS** on all 10 visual criteria.

---

## 2A. Town Hall Upgrade / Territory / Cloud Envelope Synchronization

### Root Cause Verdict
**1. Confirmed territory-preview mismatch.**

### Quantitative Reproduction (`seed = 12345`, actual production upgrade flow)
Executed via `WorldView.start_building_upgrade(th_id, rm)` -> `upgrade_progress = upgrade_required_hours` -> `WorldView.complete_upgrade(th_id, rm)`:

| Metric | Level 1 (Before Upgrade) | Level 2 (After `complete_upgrade`) |
| --- | --- | --- |
| Town Hall `upgrade_level` | `1` | `2` |
| Territory radius (`EconomyConfig.get_territory_radius`) | `13` cells | `18` cells (`24` at Level 3) |
| Territory `owned_cells` count | `365` | `685` (+320 cells) |
| Territory grid bounds | `(51, 50)` .. `(77, 76)` | `(46, 45)` .. `(82, 81)` |
| `FogOfWar` `VISIBLE` & `EXPLORED` count | `365` | `685` |
| `FogOfWar` grid bounds | `(51, 50)` .. `(77, 76)` | `(46, 45)` .. `(82, 81)` |
| `townhall_main` `preview_radius_px` | `350.0 px` | **`350.0 px` (UNCHANGED)** |
| `townhall_main` `core_radius_px` | `200.0 px` | **`200.0 px` (UNCHANGED)** |
| `TerrainPreviewRenderer` `_gpu_pass_count` | `2` | **`2` (0 GPU refresh)** |

### Diagnostic Screenshots
- Before upgrade (`L1`, `1.0x` & `0.75x`): `...\m2_c3_audit\08_upgrade_l1_zoom_100.png`, `...\m2_c3_audit\09_upgrade_l1_zoom_075.png`
- After upgrade (`L2`, `1.0x` & `0.75x`): `...\m2_c3_audit\10_upgrade_l2_zoom_100.png`, `...\m2_c3_audit\11_upgrade_l2_zoom_075.png`
- Isolated shader diagnostics (`L2`, `0.75x`):
  - `debug_mode = 1` (Fog vs Preview): `...\m2_c3_audit\12_upgrade_l2_debug1_fog_vs_preview.png` — shows the `FogOfWar` territory rectangle `(46,45)..(82,81)` (`576 x 288 px` in isometric screen space) extending horizontally past the `core_radius_px = 200 px` hole into the `200..350 px` wispy ring.
  - `debug_mode = 2` (Envelope SD): `...\m2_c3_audit\13_upgrade_l2_debug2_envelope.png` — confirms the GPU envelope remained fixed at L1 size.
  - `debug_mode = 3` (Final Cloud Alpha): `...\m2_c3_audit\14_upgrade_l2_debug3_alpha.png` — proves the visible rectangular cutout in the wispy cloud ring is produced where `unexp_factor` drops to `0.0` along the `576 x 288 px` `EXPLORED`/`VISIBLE` rectangle while `preview_alpha > 0.0`.

### Exact Production Code Path Responsible
1. `WorldView.complete_upgrade()` (`scripts/world/world_view.gd:3165-3170`) calls `territory_mgr.recalculate_territory()` and `_refresh_territory_overlay()`, and `TerritoryManager.recalculate_territory()` emits `territory_changed` -> `WorldView._on_territory_changed()` -> `refresh_world_vision()` -> `fog_of_war.recompute_vision(owned_cells, observer_specs)`.
2. `WorldView.sync_gameplay_terrain_preview_sources()` (`scripts/world/world_view.gd:4510-4521`) uses fixed constants `TOWN_HALL_PREVIEW_RADIUS_PX = 350.0` and `TOWN_HALL_CORE_RADIUS_PX = 200.0` without reading Town Hall `upgrade_level`, and `complete_upgrade()` does not call `sync_gameplay_terrain_preview_sources()`.

### Minimal Proposed Correction (Awaiting Owner Approval — Not Implemented)
1. Derive Town Hall `preview_radius_px` and `core_radius_px` deterministically from `EconomyConfig.get_territory_radius(th_level)` (which defines `{1: 13, 2: 18, 3: 24}`): scale from the approved Level 1 baseline `(350.0, 200.0)` at `radius = 13` by `float(rad) / 13.0` (e.g., L1: `350 / 200 px`, L2: `~485 / 277 px`, L3: `~646 / 369 px`) so the organic cloud core encloses the Manhattan territory rectangle at every Town Hall level.
2. Call `sync_gameplay_terrain_preview_sources()` in `WorldView.complete_upgrade()` when `b_type == "townhall"` (or in `_on_territory_changed()`), triggering exactly 1 GPU pass when radii change.

---

## 3. Fog Composition Audit
Inspected `shaders/fog/cloud_sea_composite.gdshader`:
- `VISIBLE`: `exp_cov -> 1.0`, `unexp_factor -> 0.0`, `total_alpha = 0.0` (`discard`) — no cloud or dark overlay.
- `EXPLORED_NOT_VISIBLE`: `mist_alpha` and `mist_col` are removed; `total_alpha = clamp(cloud_alpha, 0.0, 1.0) = 0.0` — no dark overlay and no artificial rectangular frame (outside preview mismatch cases).
- `UNEXPLORED` outside preview: `preview_alpha = 1.0`, `unexp_factor = 1.0` -> opaque cloud sea.
- `UNEXPLORED` inside preview: approved C1.9.1 organic cloud parting (`preview_alpha`).
- `FogOfWar` state is never mutated by `CloudSeaComposite`, `TerrainPreviewField`, or `TerrainPreviewRenderer`. Entity visibility remains strictly controlled by `FogOfWar` via `_refresh_dynamic_actor_visibility()`, `monster_mgr.refresh_visibility()`, `wildlife_mgr.refresh_visibility()`, and `poi_mgr.update_discovery()`.

---

## 4. Hunter Source Audit
Inspected `WorldView.sync_gameplay_terrain_preview_sources()` (`world_view.gd:4523-4553`) and `_sync_hunter_preview_sources_if_moved()` (`world_view.gd:4587-4614`):
- **Qualification discrepancy found:**
  - `WorldView.refresh_world_vision()` (`world_view.gd:5015-5021`) only grants beyond-territory scouting vision to citizens with `cit.get("can_scout_beyond_territory") == true`.
  - However, `sync_gameplay_terrain_preview_sources()` and `_sync_hunter_preview_sources_if_moved()` currently check `c_role == "hunter" or cit.get("can_scout_beyond_territory") == true`. Because ordinary `CitizenController` hunters do not set `can_scout_beyond_territory = true`, **ordinary Hunters currently receive a Hunter Scout preview source unintentionally** if only specialized scouting citizens are meant to qualify.
- **Lifecycle & GPU idle behavior:**
  - Facing changes (`facing_dir` -> `_screen_dir_to_vector()`) and cell movement update the single `"hunter_<cid>"` source.
  - Role change (`_on_citizen_role_changed`) and death (`_on_citizen_died`) remove `"hunter_<cid>"` cleanly.
  - Idle repeated checks trigger 0 redundant GPU passes (`_sources_equal()` dirty check).
- **Minimal proposed correction (if ordinary Hunters should not qualify):** Change `is_scout` in both `sync_gameplay_terrain_preview_sources()` and `_sync_hunter_preview_sources_if_moved()` to `cit.get("can_scout_beyond_territory") == true`.

---

## 5. Soldier Source Audit
Inspected `TacticalMilitaryManager` signal wiring (`world_view.gd:529-535`, `5261-5271`) and `sync_gameplay_terrain_preview_sources()` (`world_view.gd:4555-4575`):
- Spawn (`unit_spawned`), movement (`unit_moved`), and despawn/death (`unit_despawned`) all invoke `sync_gameplay_terrain_preview_sources()`.
- Uses deterministic single ID `"soldier_<unit_id>"` via `upsert_source()`, updating current position in place with **zero historical trail**.
- Stale IDs are pruned against `desired_ids` on every sync, so despawn, death, and Save/Load leave zero stale soldier sources.

---

## 6. Save/Load Audit
Inspected `SaveManager.apply_loaded_state_to_world()` (`save_manager.gd:2122-2124`, `2961-2967`) and `WorldView._sync_full_fog_and_minimap()` / `rebind_terrain_preview_fog()` / `_refresh_cloud_sea_composite_bindings()`:
1. `SaveManager` replaces/validates `world_view.fog_of_war` (`2122-2124`) and restores `fog_of_war` states (`2824+`).
2. `SaveManager` calls `refresh_world_vision()` (`2963`) -> `_sync_full_fog_and_minimap()` (`2965`):
   - `fog_of_war.rebuild_visible_cache()`
   - `_sync_full_fog_layer()` -> `sync_fog_state_texture_full(false)` + `_schedule_fog_transition_update()`
   - `rebind_terrain_preview_fog(fog_of_war)` -> rebinds `TerrainPreviewField._fog_of_war`, syncs renderer, refreshes `CloudSeaComposite` bindings (`envelope_tex`, `fog_state_tex`, `transition_tex`, `map_size`, `world_seed_f`)
   - `sync_gameplay_terrain_preview_sources()` -> reconstructs Town Hall / Hunter / Soldier sources and prunes stale IDs
   - `_apply_fog_presentation_visibility()`
3. Repeated `SaveManager.apply_loaded_state_to_world()` verified idempotent with no duplicate `SubViewport`, `CloudSeaComposite`, or gameplay sources, and no save schema changes.

---

## 7. Test Execution Integrity (All 17 Suites)

| # | Suite | Mode | Exit | Assertions / Completion Marker | Errors / Warnings |
| --- | --- | --- | --- | --- | --- |
| 1 | `test_c192_m2_c3_production_cloud.gd` | D3D12 | 0 | `PASS: ... (41 assertions passed, 0 failed)` | 21 ObjectDB / 8 resources at exit (standard Godot scene exit) |
| 2 | `test_cloud_sea_composite.gd` | D3D12 | 0 | `PASS: ... (24 assertions passed, 0 failed)` | 21 ObjectDB / 8 resources at exit |
| 3 | `test_cloud_sea_fog_state_composition.gd` | D3D12 | 0 | `PASS: ... (19 assertions passed, 0 failed)` | 21 ObjectDB / 8 resources at exit |
| 4 | `test_cloud_sea_visibility_safety.gd` | D3D12 | 0 | `PASS: ... (11 assertions passed, 0 failed)` | 21 ObjectDB / 8 resources at exit |
| 5 | `test_terrain_preview_gpu_equiv.gd` | D3D12 | 0 | `PASS: ... (60 assertions passed, 0 failed)` | None |
| 6 | `test_world_view_preview_lifecycle.gd` | D3D12 | 0 | `PASS: ... (16 assertions passed, 0 failed)` | 33 ObjectDB / 8 resources at exit |
| 7 | `test_terrain_preview_field.gd` | Headless | 0 | `PASS: ... (21 assertions passed, 0 failed)` | None |
| 8 | `test_fog_of_war_reconnaissance.gd` | Headless | 0 | `Passed: 127 \| Failed: 0` | None |
| 9 | `test_fog_rendering.gd` | Headless | **1** | `PHASE 3 FOG RENDERING RESULTS: 21 passed, 3 failed` | Fails 3 legacy `FogTileMapLayer` assertions skipped when `use_cloud_sea_composite == true` |
| 10 | `test_fog_debug_toggle.gd` | Headless | 0 | `PHASE 5 FOG DEBUG TOGGLE RESULTS: 15 passed, 0 failed` | 21 ObjectDB / 8 resources at exit |
| 11 | `test_fog_cloud_overlay.gd` | Headless | **1** | `FAIL: test_fog_cloud_overlay.gd (2/61 assertions failed)` | Fails 2 legacy `fog_cloud_layer` / `cloud_sea_base` assertions when `use_cloud_sea_composite == true` |
| 12 | `test_save_load.gd` | Headless | 0 | `Assertions Passed: 182 \| Failed: 0` / `ALL PHASE 8 PERSISTENCE TESTS PASSED!` | None |
| 13 | `test_repeated_save_load_scene_cleanup.gd` | Headless | 0 | `RISK-005 SUITE: ALL 38 SCENARIO CHECKS PASSED! (0 Failures)` | None |
| 14 | `test_day_night_phase1.gd` | Headless | 0 | `TEST SUITE COMPLETE: 42 passed, 0 failed` | None |
| 15 | `test_hunter_system.gd` | Headless | 0 | `[test_hunter_system] Passed: 2028 \| Failed: 0` | None |
| 16 | `test_tactical_military.gd` | Headless | 0 | `All Package 1W Tactical Military Tests PASSED! (419 assertions)` | 18 RIDs / 69 ObjectDB / 12 resources at exit |
| 17 | `test_all_scripts_load.gd` | Headless | 0 | `GAP-006 RESULTS: 231 / 231 Scripts Compiled Successfully` | None |

---

## 8. Final Git Preservation Check
- **Branch:** `feature/package-3a-outpost-garrison-reinforcement`
- **HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **`git status --short` line count:** `453` (448 pre-existing + M2-C3 deliverables; zero staging, commit, push, reset, or destructive operations performed; zero production modifications made during this audit).
- **M2-C3 production files changed:** `shaders/fog/cloud_sea_composite.gdshader`, `scripts/world/world_view.gd`.

---

## 9. Unresolved Defects & Final Verdict
1. **Blocking Defect (Section 2A):** **Confirmed territory-preview mismatch** after Town Hall upgrade (`complete_upgrade()` expands `TerritoryManager` and `FogOfWar` from radius `13` to `18`/`24`, while `townhall_main` remains hardcoded at `350.0 / 200.0 px`, carving a rectangular `EXPLORED`/`VISIBLE` cutout in the wispy cloud ring).
2. **Non-Blocking Discrepancy (Section 4):** `sync_gameplay_terrain_preview_sources()` and `_sync_hunter_preview_sources_if_moved()` match `role == "hunter" or can_scout_beyond_territory == true`, whereas `refresh_world_vision()` only checks `can_scout_beyond_territory == true`.
3. **Legacy Test Failures (Section 7):** `test_fog_rendering.gd` (3/24 failed) and `test_fog_cloud_overlay.gd` (2/61 failed) fail because they assert legacy `fog_tile_layer` / `fog_cloud_layer` / `cloud_sea_base` updates while `use_cloud_sea_composite == true`.

**Final Verdict: FAIL** — Ready for owner review and authorization of the minimal Town Hall upgrade synchronization fix (and optional Hunter/legacy test alignment).
