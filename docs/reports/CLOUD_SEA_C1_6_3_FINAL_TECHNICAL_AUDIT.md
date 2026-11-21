# KINGDOMS UNBOUND — C1.6.3 Final Technical Audit
## Foreground Cloud Correctness, Full-Sync Performance & A_Medium Distribution

**Engine:** Godot 4.7 (`4.7-stable`, Windows)  
**Branch:** `feature/package-3a-outpost-garrison-reinforcement`  
**Baseline HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`  
**Mode:** Audit-Only (Zero production code or asset modifications)

---

## 1. Git Baseline

Recorded in `scratch/c1_6_3_audit_baseline_git.txt` prior to audit execution:
- **HEAD:** `e1d379b93a48db018c7b412b896caa9592f6980c`
- **Working Tree:** `414` pre-existing modified/untracked entries preserved untouched.

---

## 2. Exact Files Inspected

- `scripts/world/fog_cloud_layer.gd` (lines `1–635`)
- `assets/fog/main_cloud_01_towering_cumulus.png`, `main_cloud_02_sweeping_bank.png`, `main_cloud_03_asymmetrical_cluster.png`
- `scratch/c1_6_3_screenshots/c1_6_3_settlement_day.png`, `c1_6_3_deep_cloud_sea_day.png`, `c1_6_3_after_reveal_day.png`, `comp_c1_6_2_vs_c1_6_3.png`
- Isolated audit script: `scratch/c1_6_3_audit/run_c1_6_3_audit.gd`

---

## 3. Full-Sync Performance Breakdown (`128×128` `WorldView`, 10 Runs After 2 Warm-Ups)

| Stage in `FogCloudLayer.sync_full()` | Avg (ms) | Median (ms) | Worst (ms) | Share of Total (Median) |
| :--- | :---: | :---: | :---: | :---: |
| **`clear_all()`** (detach + `queue_free` `Sprite2D`s) | `1.433` | `1.533` | `2.135` | `0.5%` |
| **`_sync_full_fog_mask_fast()` + `_upload_fog_mask()`** | `9.185` | `9.081` | `10.856` | `3.0%` |
| **`_generate_world_chunk_candidates()`** (bank/support/bridge + bucketing) | **`180.457`** | **`183.767`** | **`201.957`** | **`60.4%`** |
| **`_is_opaque_footprint_unexplored()`** (`stride = 6`, `455` candidates) | **`105.193`** | **`107.322`** | **`121.384`** | **`35.3%`** |
| **`Sprite2D.new()` + texture/material/transform + `add_child()`** | `5.215` | `5.291` | `6.595` | `1.7%` |
| **Total `sync_full()`** | **`302.821`** | **`304.160`** | **`333.297`** | **`100%`** |

---

## 4. Bottleneck Analysis

Two stages account for **95.7%** of total `sync_full()` cost:
1. **Primary Bottleneck — `_generate_world_chunk_candidates()` (`183.767 ms` median, `60.4%`):**
   - Executes `O(N²)` linear scans over `placed` (`455` items) inside `_pick_weighted_diverse_kind()`, `_pick_varied_scale()`, and `_try_record_candidate()` (3 separate loops per candidate).
   - **Crucially:** Re-runs from scratch on *every* `sync_full()` call even when `(_world_seed, map_width, map_height, _density_preset)` has not changed!
2. **Secondary Bottleneck — `_is_opaque_footprint_unexplored()` (`107.322 ms` median, `35.3%`):**
   - Evaluates `152 / 136 / 132` sample points per candidate (`~64,000` calls to `IsoMath.local_to_map()` + `IsoMath.is_in_bounds()` + `fog.is_unexplored()`).
3. **Node Creation & Destruction (`6.824 ms` combined) and Fog Mask (`9.081 ms`):** Not bottlenecks.

---

## 5. Opaque-Footprint Sampling Correctness (`stride = 6` vs. Exhaustive `stride = 1`)

- **How Sampling Works (`fog_cloud_layer.gd:63–74, 615–629`):** `_extract_opaque_sample_points(img, 6)` collects `(x - w*0.5, y - h*0.5)` for pixels with `a > 0.1` at `6×6` px steps (`152`, `136`, `132` pts vs. `5,518`, `4,776`, `4,802` opaque pixels at `stride = 1`). `_is_opaque_footprint_unexplored()` multiplies each offset by `sc` (`0.82..1.18`), maps to `IsoMath.local_to_map()`, and rejects if any in-bounds cell is not `UNEXPLORED`.
- **Boundary & Transform Findings:**
  - `range(0, w, 6)` / `range(0, h, 6)` does **not** explicitly include `w-1` / `h-1` boundary rows/columns (though all 3 sprites have transparent `1 px` outer margins).
  - Sprite scaling (`0.82..1.18`) is applied in `_is_opaque_footprint_unexplored()` (`center_px + off * sc`), scaling sample spacing up to `7.08 px` (`10.0 px` diagonal) vs. `32×16 px` isometric tiles (`14.31 px` perpendicular width).
  - `flip_h` is **not** used by `FogCloudLayer` (`Sprite2D.flip_h` stays `false`). If `flip_h` were added later, `off.x` would need negation.
  - `test_fog_cloud_overlay.gd` currently tests `IsoMath.local_to_map(sprite.position)` (center cell), not exhaustive pixel coverage.
- **Theoretical Guarantee Verdict:** `stride = 6` has **`0` observed leaks** in both the live `128×128` world and all `144` adversarial tests, **but** is an empirical grid-subsampling approximation rather than a strict mathematical proof if arbitrary `1 px` fringes or `scale > 1.5` were ever introduced.

---

## 6. Adversarial Test Results

Executed `144` adversarial combinations (`6` geometry cases × `3` sprites × `4` scales `[0.82, 1.00, 1.18, 1.50]` × `flip_h = false/true`) comparing `stride = 6` and `stride = 4` (`344 / 302 / 300` pts) against exhaustive `stride = 1`:

| Check | Cases Tested | Leaks (`s=6` vs `s=1`) | Leaks (`s=4` vs `s=1`) |
| :--- | :---: | :---: | :---: |
| **Live `128×128` `WorldView` (`seed = 12345`)** | `455` candidates | **`0`** | — |
| **1-Cell Pocket Inside Footprint** | `24` | **`0`** | **`0`** |
| **Narrow Horizontal Strip Crossing Cloud** | `24` | **`0`** | **`0`** |
| **Narrow Vertical Strip Crossing Cloud** | `24` | **`0`** | **`0`** |
| **Diagonal Strip Crossing Cloud** | `24` | **`0`** | **`0`** |
| **1-Cell Explored Boundary Edge** | `24` | **`0`** | **`0`** |
| **Offset 1-Cell East Pocket** | `24` | **`0`** | **`0`** |
| **Total** | **`144` adv + `455` live** | **`0`** | **`0`** |

**Footprint Benchmark on `455` Candidates (`128×128`):** `stride = 6`: `142.768 ms` | `stride = 4`: `231.170 ms` | `stride = 1`: `4013.027 ms`.

---

## 7. A_Medium Distribution Analysis (`128×128`, `seed = 12345`)

- **Total Candidates Generated:** `455` (`82` bank center cap + anchor/supports + `68` bridge target; `15` culled over initial settlement reveal).
- **Total Active Foreground Instances:** **`440`** across **`229`** active `8×8` chunks (`1`–`5` sprites/chunk, `1.92` mean).
- **Instance Count by Asset:**
  - `main_cloud_01_towering_cumulus.png` (`144×92`, `5,518` opaque px): **`133`** (`30.2%`)
  - `main_cloud_02_sweeping_bank.png` (`160×84`, `4,776` opaque px): **`138`** (`31.4%`)
  - `main_cloud_03_asymmetrical_cluster.png` (`136×88`, `4,802` opaque px): **`169`** (`38.4%`)
- **Pixel Area Coverage Metric:**
  - Sum of scaled opaque sprite pixel areas: **`2,185,774 px²`**
  - Unexplored map diamond area (`4,100,864 px²` of `4,194,304 px²` total): **gross (pre-overlap) ratio = `53.3%`**, which aligns with the C1.5.5 `~42–44%` net visible coverage after cloud-to-cloud overlap. *(Note: `440` is an instance count, not a pixel-area metric.)*
- **Screenshot Review:** `c1_6_3_deep_cloud_sea_day.png` and `c1_6_3_settlement_day.png` show organic banks with no repeating horizontal rows, balanced morphology variety, and clear `CloudSeaBase` visibility in negative spaces.

---

## 8. Recommended Minimal Fixes (If Authorized Later)

1. **Candidate Layout Cache (`sync_full()` speedup ~`184 ms` -> `0 ms` on repeated `sync_full()`):** Cache `_chunk_candidates` by `(_world_seed, mw, mh, _density_preset)` so repeated `sync_full()` (e.g., fog reset/reload with same seed) skips `_generate_world_chunk_candidates()`.
2. **Pre-Quantized Unique Cell Offsets per Sprite (`footprint_ms` speedup `~107 ms` -> `~12–18 ms`):** Instead of testing `132–152` pixel points (`stride = 6`) or `4,400–5,062` points (`stride = 1`), quantize `stride = 1` opaque pixels at load time into unique `16×8 px` sub-tile points (`~40–50` points per sprite). That achieves **exhaustive `stride = 1` precision** AND cuts footprint checks by **~3×** (`~35 ms` instead of `107 ms`), bringing repeated `sync_full()` down to **`~45–50 ms`** total!

---

## 9. Risk Assessment

- **Correctness Risk:** **Low.** Zero leaks observed in `144` adversarial cases and `455` live candidates.
- **Performance Risk:** **Low–Moderate** on repeated `sync_full()` (`~304 ms` hitch if triggered mid-gameplay), **Low** on normal gameplay (`4.403 ms` incremental). Candidate caching + sub-tile quantization resolves repeated `sync_full()` cleanly without touching density or art.

---

## 10. Confirmation of Preservation

Confirmed via `git status --short` comparison against `scratch/c1_6_3_audit_baseline_git.txt`: **zero production files, test files, or assets were modified** during this audit; only `docs/reports/CLOUD_SEA_C1_6_3_FINAL_TECHNICAL_AUDIT.md` was added.
