# EXECUTIVE AUDIT REPORT — KINGDOMS UNBOUND (REVISED V2)

- **Date:** 2026-11-07 · **Auditor:** Independent Principal Architecture & Codebase Review
- **Engine:** Godot 4.7-stable (GDScript, Forward+, Jolt Physics 3D)
- **Repository / Branch:** `Mincow271104/KINGDOMS-UNBOUND` @ `feature/package-2j-army-equipment-progression`
- **Committed Baseline HEAD:** `4a99322a6d2efb6bc269914f68d2968734d4b678` (`fix(package-2j): complete warning cleanup and closure verification`)
- **RC2 Baseline Ancestor:** `5b489407fdd011ec102f0e46d104e7f0241f99d7`
- **Workspace State:** Package 2J committed cleanly (19 files). Working tree contains isolated, uncommitted AI M2-B prototype work and uncommitted `project.godot` display setting change.

---

## 1. Scope & Methodology Statement

This audit synthesizes static source code analysis, call-graph tracing, and test evidence reconciliation:
1. **Original Claude Sonnet 5.5 Audit:** Sampled 15–20% of production GDScript in full (economy core, job/workplace logistics, citizen cargo & death lifecycle, `WorldView` lifecycle/input/simulation handlers, `SaveManager` load/rollback path, `FieldSiegeManager`, `BattleCampaignManager` offensive/raid flow, player army recruitment & equipment tier authority, faction diplomacy public signalling APIs).
2. **Post-Package 2J Independent Reconciliation:** All findings were re-verified against committed HEAD `4a99322` and current working-tree state.
3. **Evidence Distinction:** Distinguishes unit tests, headless integration tests, automated GUI harnesses, and unassisted manual gameplay acceptance.

---

## 2. Issue & Invariant Counts

| Category | Count | Item Identifiers | Summary Status |
|:---|:---:|:---|:---|
| **Critical Defects** | 0 | — | No catastrophic blockers or data corruptions detected. |
| **High Defects** | 0 | — | None. |
| **Confirmed Bugs (Static)** | 1 | `BUG-001` | Open — hauler cargo destroyed on citizen death. |
| **Probable Bugs** | 2 | `BUG-002`, `BUG-003` | Open — job accumulation (unprofiled) and autosave slot collision. |
| **Architectural Risks** | 8 | `RISK-001`..`RISK-008` | 1 Closed (`RISK-006`); 1 Confirmed Open (`RISK-008`); 6 Open/Latent. |
| **Test Coverage Gaps** | 7 | `GAP-001`..`GAP-007` | 1 Closed (`GAP-001`); 6 Open (including `GAP-002` runner). |
| **Baseline Limitations** | 1 | `BASELINE-001` (`TC-ARMY.32`) | Confirmed pre-existing limitation inherited from Package 2F. |
| **Core Invariants (I-01..I-15)** | 15 | I-01..I-15 | **11 VERIFIED**, **3 PARTIAL** (I-05, I-10, I-15), **1 VIOLATED** (I-03). |

---

## 3. Executive Findings Summary

1. **BUG-001 (Medium, Confirmed Static):** Hauler cargo ($\le 10$ units) is destroyed when a citizen dies (`scripts/entities/citizen_controller.gd` L770–799; `scripts/world/world_view.gd` L570–605). When famine strikes, starving haulers carrying food perish, and the carried food is deleted with the node rather than returned to workplace buffer or stock.
2. **RISK-008 (Low/Medium, Confirmed Static):** HUD offensive-campaign feedback displays a successful completion banner (`⚔️ Đã hoàn thành chiến dịch tấn công!`) and plays a click sound even when the player's force was defeated (`HEAD:scripts/ui/hud.gd` L1167–1186; `HEAD:scripts/combat/battle_campaign_manager.gd` L805–809). The HUD evaluates only `res["success"]` (which indicates simulation execution success), ignoring `report.victor`.
3. **GAP-001 & RISK-006 Successfully Closed in Package 2J:**
   - `GAP-001`: Dedicated tracked failure-path regression test `scripts/test/test_world_view_siege_input.gd` (193 lines, 30 checks PASS, Exit Code 0) was committed to HEAD.
   - `RISK-006`: `docs/KNOWN_ISSUES.md` (`ISSUE-006`) and `docs/WORKLOG.md` were updated and synchronized with the working tree in commit `4a99322`.
4. **BUG-002 (Medium, Probable):** Dynamic non-recurring jobs (`is_recurring = false`) remain in `JobManager._jobs` with state `COMPLETED` forever. Memory grows monotonically over long gameplay sessions.
5. **BUG-003 (Medium, Probable / Product Intent):** Daily autosave writes to `user://saves/world_save.json`, silently overwriting the player's manual save slot.
6. **Autoload Configuration Reality:** `project.godot` defines **exactly five engine autoload singletons**: `MCPRuntime` (tooling), `TimeManager`, `ResourceManager`, `EventManager`, and `AudioManager`. All other managers (`JobManager`, `WorkplaceManager`, `FactionManager`, `PlayerArmyManager`, `FieldSiegeManager`, etc.) are non-autoload `RefCounted` instances owned by `WorldView`.

---

## 4. Subsystems Assessed as Healthy (Committed Source)

- **Central Resource Ledger:** Single source of truth in `ResourceManager`, atomic credit/debit helpers (`add_resources_atomic`), and demolition refund logic.
- **Player Equipment Authority:** Strictly owned by `PlayerArmyManager` (tiers 1..3 as strict integers), protected by fail-closed save validation.
- **NPC vs Player Multiplier Separation:** NPC units maintain fixed 1.0 multiplier and do not steal player equipment bonuses.
- **Field Siege Lifecycle:** One active siege per objective, clean terminal resolution, withdrawal/defeat handling, and retry idempotency.
- **AI Diplomacy Routing:** Routes through public signalling APIs (`declare_war`, `propose_treaty`), properly firing signals that cancel raids and active sieges.
- **Save/Load Integrity:** Pre-validation fail-closed checks, pre-load snapshotting with recursive rollback on military deserialize failure, and cross-file crash recovery for Treasury Conversion.

---

## 5. Prioritized Recommended Next Steps

1. **Bug Resolution (Pre-Next Package):**
   - Resolve **BUG-001**: Add resource refund logic on citizen death before node queue_free, accompanied by conservation tests.
   - Resolve **RISK-008**: Update `HUD.attack_faction()` to inspect `report.victor` and render outcome-accurate victory vs defeat banners.
2. **Product Intent Clarification:**
   - Decide **BUG-003**: Introduce separate `autosave.json` slot or expose configurable autosave intervals without schema breaking.
   - Clarify **RISK-004**: Clarify whether faction elimination/exile should be triggered by conquest or remains a future mechanic.
3. **Test Infrastructure Hardening:**
   - Address **GAP-002**: Implement a tracked regression runner reporting process exit codes rather than heuristic regex counts.
   - Address **GAP-006**: Add a headless all-scripts parse check to prevent compile-time `preload` shadowing errors.
4. **Knowledge Base Adoption:**
   - Adopt the revised documents under `docs/architecture/`, `docs/quality/`, and `.agents/skills/`.
   - Maintain root `AGENTS.md` as the authoritative, inviolable project rule file.
