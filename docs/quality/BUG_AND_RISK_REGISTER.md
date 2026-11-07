# DEFECT, RISK & TEST COVERAGE REGISTER — KINGDOMS UNBOUND (REVISED V2)

> **Last Verified:** 2026-11-07 against committed Baseline HEAD `4a99322a6d2efb6bc269914f68d2968734d4b678`.
> Detailed Technical Findings: `DETAILED_BUG_FINDINGS.md` and `TEST_COVERAGE_GAP_ANALYSIS.md`.

---

## 1. Confirmed Defects (Bugs)

| ID | Sev | Title | Core Evidence & Files | Status |
|:---|:---:|:---|:---|:---:|
| **BUG-001** | Medium | Hauler cargo destroyed on citizen death | `scripts/entities/citizen_controller.gd` L770–799; `scripts/world/world_view.gd` L570–605. Resolved via `recover_cargo()` and `test_hauler_death_cargo_conservation.gd`. | **CLOSED** (Resolved in Post-2J Fixes) |

---

## 2. Probable Defects (Bugs / Design Questions)

| ID | Sev | Title | Core Evidence & Files | Status |
|:---|:---:|:---|:---|:---:|
| **BUG-002** | Medium | Dynamic non-recurring jobs never pruned from `JobManager._jobs` | `scripts/jobs/job_manager.gd` L275–350. Pruned non-recurring terminal jobs (`COMPLETED`, `CANCELLED`) while preserving recurring jobs and active/in-progress jobs. Bounded terminal history (50). | **CLOSED** (Resolved in Batch 2) |
| **BUG-003** | Medium | Daily autosave overwrites manual save slot `world_save.json` | `scripts/world/world_view.gd` L59–60, L2541; `scripts/persistence/save_manager.gd` L10–38. Dedicated autosave slot `user://saves/autosave.json` with independent `.bak` rotation and UI recovery actions. | **CLOSED** (Resolved in Batch 2) |

---

## 3. Architectural & Operational Risks

| ID | Sev | Title | Core Evidence & Files | Status |
|:---|:---:|:---|:---|:---:|
| **RISK-001** | Low | `commit_cost()` trusts caller and silently clamps to 0 | `scripts/economy/resource_manager.gd` L131–230. Enforced strict reservation matching, fail-closed validation, and ticket-based transaction API. Verified in `test_resource_transaction_integrity.gd` (88/88 checks PASS). | **CLOSED** (Resolved in Batch 3) |
| **RISK-002** | Low | Resolved siege records accumulate and evaluate every frame | `scripts/combat/field_siege_manager.gd` L420–640; `scripts/persistence/save_manager.gd` L1545–1575. Separated active sieges from resolved history (bounded at 50 FIFO), erased resolved sieges from `active_sieges`, and normalized legacy saves during deserialization. Verified in `test_siege_record_lifecycle.gd` (51/51 checks PASS). | **CLOSED** (Resolved in Batch 3) |
| **RISK-003** | Low | `TacticalUnit.faction_id` defaults to `"player"` | `scripts/military/enemy_tactical_unit.gd` L31–38. Added explicit `_init()` initializing `faction_id = "enemy"` immediately upon instance allocation, preventing unparented or unready enemy units from ever defaulting to `"player"`. Verified in `test_enemy_military_ai.gd` (54/54) and `test_tactical_combat.gd` (58/58). | **CLOSED** (Hardened in Batch 3) |
| **RISK-004** | Low | Faction `in_exile` and `eliminated` statuses unreachable | `scripts/factions/faction_data.gd` L28–36; `scripts/factions/faction_strategy_planner.gd` L92–115; `scripts/factions/faction_diplomacy_planner.gd` L170–178. Full fail-closed support implemented for exile and elimination. Per GDD, full faction elimination is designed for endgame campaign packages, while outpost conquest is implemented via Field Siege in Package 1X/2J. | **RESOLVED** (Design Alignment) |
| **RISK-005** | Low | SaveManager load frees citizens via `queue_free()` without `remove_child()` | `scripts/persistence/save_manager.gd` L1950–1956. Citizens container immediately removes child before `queue_free()` to prevent duplicate name auto-renaming (`@Node2D@xxxx`) during same-frame world reload. Verified in `test_repeated_save_load_scene_cleanup.gd` (38/38 checks PASS). | **CLOSED** (Resolved in Batch 3) |
| **RISK-006** | Medium | Documentation drift from working-tree changes | `docs/KNOWN_ISSUES.md` (ISSUE-006) and `docs/WORKLOG.md` synchronized in commit `4a99322`. | **CLOSED** (Resolved in `4a99322`) |
| **RISK-007** | Low | Stock may exceed storage capacity after demolition | `scripts/economy/resource_manager.gd` L453–462; `scripts/economy/building_system.gd` L458–473. Intentional non-destructive resource conservation: existing stock is never destroyed upon demolition, while further additions are strictly blocked by capacity checks. Formalized in `docs/architecture/CORE_INVARIANTS.md` (I-07). | **RESOLVED** (Design Intent) |
| **RISK-008** | Low/Med | HUD offensive campaign banner reports completion regardless of battle outcome | `scripts/ui/hud.gd` L1167–1205. Resolved by evaluating `report.victor` into truthful victory/defeat/stalemate branches. Verified in `test_campaign_result_feedback.gd`. | **CLOSED** (Resolved in Post-2J Fixes) |

---

## 4. Test Coverage Gaps (Quality Infrastructure)

| ID | Sev | Gap Description | Current Status & Recommended Remediation |
|:---|:---:|:---|:---|
| **GAP-001** | Medium | Attack-order failure branch in `world_view.gd` lacked tracked test | **CLOSED (RESOLVED in Commit `4a99322`)** via `scripts/test/test_world_view_siege_input.gd` (30/30 checks PASS, Exit Code 0). |
| **GAP-002** | Medium | No tracked regression runner; scratch runners count regex words | **CLOSED (RESOLVED in Batch 2)** via `scripts/test/run_regression.ps1` with raw exit codes, baseline detection, and JSON summary. |
| **GAP-003a** | Medium | Missing unit test for hauler cargo conservation (`BUG-001`) | **CLOSED (RESOLVED in Batch 2)** via `scripts/test/test_hauler_death_cargo_conservation.gd` (12/12 PASS, Exit Code 0). |
| **GAP-003b** | Medium | Missing unit test for job lifecycle pruning bounds (`BUG-002`) | **CLOSED (RESOLVED in Batch 2)** via `scripts/test/test_job_lifecycle_pruning.gd` (10/10 PASS, Exit Code 0). |
| **GAP-003c** | Medium | Missing unit test for autosave slot isolation (`BUG-003`) | **CLOSED (RESOLVED in Batch 2)** via `scripts/test/test_save_slot_isolation.gd` (10/10 PASS, Exit Code 0). |
| **GAP-004** | Low | Heavy reliance on private internals in test suites | **OPEN** — $>480$ direct accesses to `._x` fields reduce refactoring resistance. |
| **GAP-005** | Medium | Gameplay acceptance evidence lives in untracked artifacts | **OPEN / PARTIALLY ADDRESSED** — Distinguished in WORKLOG, but lacks structured tracked checklists. |
| **GAP-006** | Low | Absence of a tracked all-scripts compile/parse check | **CLOSED (RESOLVED in Batch 2)** via `scripts/test/test_all_scripts_load.gd` (124/124 scripts compiled cleanly, PASS). |
| **GAP-007** | Low | Simulation baseline runner aborts without user:// isolation | **CLOSED (RESOLVED in Batch 2)** — Standardized environment isolation recipe documented in `TEST_COVERAGE_GAP_ANALYSIS.md`. |

---

## 5. Existing Baseline Limitations (Not Regressions)

| ID | Item | Evidence & Cause | Governance Classification |
|:---|:---|:---|:---|
| **BASELINE-001** | `test_player_army.gd` `TC-ARMY.32` fails | `scripts/test/test_player_army.gd`: `[FAIL] TC-ARMY.32: Damaged barracks still provides capacity: 5` (Exit Code 1). `WorldView.set_building_state()` rejected `"damaged"` in Package 2F (commit `a55021c`). | **Confirmed Pre-Existing Baseline Limitation** (`docs/KNOWN_ISSUES.md` `ISSUE-006`). |

---

## 6. Previously Fixed Issues & Verification Status

| ID | Fix Description | Implementation Location | Verified Test Evidence |
|:---|:---|:---|:---|
| **FIXED-001** | `world_view.gd` red banner on attack-order failure | `scripts/world/world_view.gd` L1097–1103 | Tracked suite `scripts/test/test_world_view_siege_input.gd` (30/30 checks PASS). |
| **FIXED-002** | Test parse errors from `const` shadowing ClassDB | `test_factions_and_battles.gd`, `test_faction_diplomacy_ai.gd` | Both suites pass cleanly (Exit Code 0). |
| **FIXED-003** | Variable shadowing across 14 production files | Production scripts | GDScript warning cleanup completed; 23/24 suites pass. |
