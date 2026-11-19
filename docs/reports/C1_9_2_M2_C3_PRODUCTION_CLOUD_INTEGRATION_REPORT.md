# KINGDOMS UNBOUND — C1.9.2 M2-C3
## Production Cloud Integration, Zero Overlay, Gameplay Preview & Save/Load Hardening Report

**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Base HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Engine:** Godot 4.7-stable (D3D12 Forward+ / NVIDIA GeForce RTX 3050 Ti Laptop GPU)  
**Status:** Complete — Ready for Owner Review (no commit/push performed)

---

## 1. Summary of Production Changes

### Phase B — Zero Overlay Shader Correction
- **`shaders/fog/cloud_sea_composite.gdshader`**:
  - Removed the `mist_alpha` (`0.46`) and `mist_col` dark overlay on `EXPLORED_NOT_VISIBLE` terrain so `total_alpha = clamp(cloud_alpha, 0.0, 1.0)` and `COLOR = vec4(cloud_col, total_alpha)`.
  - Preserved `UNEXPLORED` cloud sea coverage, smooth `exp_cov` transition edges, `debug_mode` views, and single `World/DayNightModulate` color inheritance.

### Phase C — Gameplay `TerrainPreviewField` Source Integration
- **`scripts/world/world_view.gd`**:
  - Added `sync_gameplay_terrain_preview_sources()` and `_sync_hunter_preview_sources_if_moved()`:
    - **Town Hall (`townhall_main`)**: Dynamically resolved via `_resolve_active_townhall_cell()` from active `townhall` building in `world_data.buildings` (e.g. `(63, 62)` on `seed = 12345`), with `TOWN_HALL_PREVIEW_RADIUS_PX = 350.0` and `TOWN_HALL_CORE_RADIUS_PX = 200.0`. Removed cleanly when Town Hall transitions to `"destroyed"` and restored when active.
    - **Hunter / Scout (`hunter_<citizen_id>`)**: Registered for living citizens with `role == "hunter"` or `can_scout_beyond_territory == true`, including directional bias vector computed from `facing_dir` via `_screen_dir_to_vector()`. Updated on movement/facing change without redundant GPU passes when idle; removed cleanly on role change or death (`_on_citizen_died`).
    - **Soldiers (`soldier_<unit_id>`)**: Registered for living tactical units from `tactical_military_mgr.get_all_units()` using current position only (zero trail) and `Vector2.ZERO` direction. Updated via `_on_tactical_unit_spawned`, `_on_tactical_unit_moved`, and `_on_tactical_unit_despawned`.

### Phase D — Save/Load & Renderer Lifecycle Hardening
- **`scripts/world/world_view.gd`**:
  - Updated `rebind_terrain_preview_fog()` and `_sync_full_fog_and_minimap()` to rebind `TerrainPreviewField` to the restored `FogOfWar`, resync `fog_state_tex` + `FogTransitionViewport`, resync gameplay preview sources via `sync_gameplay_terrain_preview_sources()`, and refresh `CloudSeaComposite` shader bindings via `_refresh_cloud_sea_composite_bindings()`.
  - Verified idempotency across repeated `SaveManager.apply_loaded_state_to_world()` calls without modifying `SaveManager` save schema.

### Phase E — Production Presentation Activation
- **`scripts/world/world_view.gd`**:
  - Activated `use_cloud_sea_composite: bool = true` as the production default.
  - Centralized visibility in `_apply_fog_presentation_visibility()` (called from `_setup_fog_layer()`, `_sync_full_fog_and_minimap()`, `_refresh_cloud_sea_composite_bindings()`, and `set_debug_fog_disabled()`), hiding `fog_tile_layer`, `fog_cloud_layer`, and `cloud_sea_base` when `CloudSeaComposite` is active (zero duplicate rendering), and hiding all fog layers when `debug_fog_disabled == true`.
  - Skipped legacy `fog_tile_layer` and `fog_cloud_layer` dirty-cell updates in `_update_fog_visuals()` when `use_cloud_sea_composite` is active.

---

## 2. Files Modified & Created

### Production Files Modified
- `shaders/fog/cloud_sea_composite.gdshader`
- `scripts/world/world_view.gd`

### Test Files Created / Updated
- Created: `scripts/test/test_c192_m2_c3_production_cloud.gd` (41 assertions)
- Updated for Zero Overlay / M2-C3 production default:
  - `scripts/test/test_cloud_sea_fog_state_composition.gd`
  - `scripts/test/test_cloud_sea_composite.gd`
  - `scripts/test/test_world_view_preview_lifecycle.gd`
  - `scripts/test/test_fog_debug_toggle.gd`

---

## 3. Automated Validation Results

| Test Suite | Mode | Result | Notes |
| --- | --- | --- | --- |
| `test_c192_m2_c3_production_cloud.gd` | D3D12 | **PASS (41/41)** | Zero-overlay, Town Hall/Hunter/Soldier lifecycle, zero trail, Save/Load rebind & repeated load, entity visibility safety (`VISIBLE` / `EXPLORED_NOT_VISIBLE` / `UNEXPLORED`) |
| `test_cloud_sea_composite.gd` | D3D12 | **PASS (24/24)** | Production activation, legacy layers hidden, zoom 1.5x, cleanup |
| `test_cloud_sea_fog_state_composition.gd` | D3D12 | **PASS (19/19)** | Zero dark overlay on `EXPLORED_NOT_VISIBLE` (`a=0.00`), `UNEXPLORED` cloud sea (`a=1.00`) |
| `test_cloud_sea_visibility_safety.gd` | D3D12 | **PASS (11/11)** | Props, POIs, wildlife, monsters, enemy military gated strictly by `FogOfWar` |
| `test_terrain_preview_gpu_equiv.gd` | D3D12 | **PASS (60/60)** | CPU/GPU envelope equivalence, dirty-state & overflow priority |
| `test_world_view_preview_lifecycle.gd` | D3D12 | **PASS (16/16)** | Ownership, rebind, cleanup, multi-instance isolation |
| `test_all_scripts_load.gd` | Headless | **PASS (231/231)** | All 231 project scripts compile cleanly |
| `test_terrain_preview_field.gd` | Headless | **PASS (21/21)** | Source registry, no-trail, directional bias, determinism |
| `test_fog_of_war_reconnaissance.gd` | Headless | **PASS (Exit 0)** | FogOfWar gameplay semantics & reconnaissance |
| `test_fog_debug_toggle.gd` | Headless | **PASS (15/15)** | Debug toggle, minimap safety, save/load reset |
| `test_save_load.gd` | Headless | **PASS (Exit 0)** | Full save/load & backup recovery |
| `test_repeated_save_load_scene_cleanup.gd` | Headless | **PASS (Exit 0)** | Repeated save/load stability |
| `test_day_night_phase1.gd` | Headless | **PASS (Exit 0)** | Single `World/DayNightModulate` & phase progression |
| `test_hunter_system.gd` | Headless | **PASS (Exit 0)** | Hunter system behavior |
| `test_tactical_military.gd` | Headless | **PASS (419 assertions, Exit 0)** | Tactical military & army state machine |

---

## 4. Live Visual & Performance Verification (D3D12 Forward+, `seed = 12345`)

- **Screenshots Captured & Inspected** (Town Hall centered at `(63, 62)`):
  - Zoom `0.75x`, `1.0x`, `1.5x` (Day `12.0h`): Clean organic cloud opening, zero dark rectangular overlay, zero isometric tile-diamond edges, coherent world-space cloud textures.
  - Dawn (`5.5h`), Dusk (`18.5h`), Night (`23.0h`) at `1.0x`: Single `World/DayNightModulate` tints terrain and clouds harmoniously across all times of day.
- **Performance Benchmarks (30 idle frames on D3D12 Forward+)**:
  - `1x` resolution: `avg_frame_ms = 7.010 ms`, `idle_uploads = 0`, `idle_transition = 0`, `idle_preview_passes = 0`
  - `2x` resolution: `avg_frame_ms = 6.803 ms`, `idle_uploads = 0`, `idle_transition = 0`, `idle_preview_passes = 0`

---

## 5. Next Action
Awaiting owner review and approval before any commit or further changes.
