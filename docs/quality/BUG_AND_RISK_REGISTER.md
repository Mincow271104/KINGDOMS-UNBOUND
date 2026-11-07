# DEFECT, RISK & TEST COVERAGE REGISTER — KINGDOMS UNBOUND (REVISED V2)

> **Last Verified:** 2026-11-07 against committed Baseline HEAD `4a99322a6d2efb6bc269914f68d2968734d4b678`.
> Detailed Technical Findings: `DETAILED_BUG_FINDINGS.md` and `TEST_COVERAGE_GAP_ANALYSIS.md`.

---

## 1. Confirmed Defects (Bugs)

| ID | Sev | Title | Core Evidence & Files | Status |
|:---|:---:|:---|:---|:---:|
| **BUG-001** | Medium | Hauler cargo destroyed on citizen death | `scripts/entities/citizen_controller.gd` L770–799; `scripts/world/world_view.gd` L570–605. Goods ($\le 10$) freed with citizen node. | **OPEN** (Confirmed Static) |

---

## 2. Probable Defects (Bugs / Design Questions)

| ID | Sev | Title | Core Evidence & Files | Status |
|:---|:---:|:---|:---|:---:|
| **BUG-002** | Medium | Dynamic non-recurring jobs never pruned from `JobManager._jobs` | `scripts/jobs/job_manager.gd` L208–230, L306–316. `remove_job()` has no production caller. Array grows monotonically over session. | **OPEN** (Probable / Growth Certain) |
| **BUG-003** | Medium | Daily autosave overwrites manual save slot `world_save.json` | `scripts/world/world_view.gd` L59–60, L2474–2478; `scripts/persistence/save_manager.gd` L8. Manual save overwritten on day rollover. | **OPEN** (Probable / Product Intent) |

---

## 3. Architectural & Operational Risks

| ID | Sev | Title | Core Evidence & Files | Status |
|:---|:---:|:---|:---|:---:|
| **RISK-001** | Low | `commit_cost()` trusts caller and silently clamps to 0 | `scripts/economy/resource_manager.gd` L131–137. | **OPEN** (Latent API Hazard) |
| **RISK-002** | Low | Resolved siege records accumulate and evaluate every frame | `scripts/combat/field_siege_manager.gd` L399–408, L507–508; `scripts/world/world_view.gd` L833–839. | **OPEN** |
| **RISK-003** | Low | `TacticalUnit.faction_id` defaults to `"player"` | `scripts/military/tactical_unit.gd` L34, L102–111; `scripts/military/enemy_tactical_unit.gd` L31–35. | **OPEN** (Latent Hazard) |
| **RISK-004** | Low | Faction `in_exile` and `eliminated` statuses unreachable | `scripts/factions/faction_data.gd` L180; `scripts/factions/faction_manager.gd` L446–452. | **OPEN** (Product Question) |
| **RISK-005** | Low | SaveManager load frees citizens via `queue_free()` without `remove_child()` | `scripts/persistence/save_manager.gd` L1901–1913. Same-name collision for 1 frame. | **OPEN** (Unverified) |
| **RISK-006** | Medium | Documentation drift from working-tree changes | `docs/KNOWN_ISSUES.md` (ISSUE-006) and `docs/WORKLOG.md` synchronized in commit `4a99322`. | **CLOSED** (Resolved in `4a99322`) |
| **RISK-007** | Low | Stock may exceed storage capacity after demolition | `scripts/economy/resource_manager.gd` L284–290; `scripts/economy/building_system.gd` L458–473. | **OPEN** (Design Intent) |
| **RISK-008** | Low/Med | HUD offensive campaign banner reports completion regardless of battle outcome | `HEAD:scripts/ui/hud.gd` L1167–1186; `HEAD:scripts/combat/battle_campaign_manager.gd` L805–809. Checks `res["success"]`, ignores `report.victor`. | **OPEN** (Confirmed Static) |

---

## 4. Test Coverage Gaps (Quality Infrastructure)

| ID | Sev | Gap Description | Current Status & Recommended Remediation |
|:---|:---:|:---|:---|
| **GAP-001** | Medium | Attack-order failure branch in `world_view.gd` lacked tracked test | **CLOSED (RESOLVED in Commit `4a99322`)** via `scripts/test/test_world_view_siege_input.gd` (30/30 checks PASS, Exit Code 0). |
| **GAP-002** | Medium | No tracked regression runner; scratch runners count regex words | **OPEN** — Requires tracked runner executing child processes and verifying raw exit codes. |
| **GAP-003** | Medium | Missing unit tests for confirmed/probable bugs | **OPEN** — Requires tests for cargo conservation (`BUG-001`), job pruning bounds (`BUG-002`), and autosave slot isolation (`BUG-003`). |
| **GAP-004** | Low | Heavy reliance on private internals in test suites | **OPEN** — $>480$ direct accesses to `._x` fields reduce refactoring resistance. |
| **GAP-005** | Medium | Gameplay acceptance evidence lives in untracked artifacts | **OPEN / PARTIALLY ADDRESSED** — Distinguished in WORKLOG, but lacks structured tracked checklists. |
| **GAP-006** | Low | Absence of a tracked all-scripts compile/parse check | **OPEN** — Requires a headless test loading all `res://scripts/**/*.gd` to catch `const` shadowing ClassDB. |
| **GAP-007** | Low | Simulation baseline runner aborts without user:// isolation | **OPEN** — Undocumented environment isolation recipe causes fail-closed abort. |

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
