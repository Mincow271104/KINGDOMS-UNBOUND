# ADOPTION REVIEW & COMPARATIVE SYNTHESIS — AGENT KNOWLEDGE BASE V2

- **Review Date:** 2026-11-07
- **Baseline Committed HEAD:** `4a99322a6d2efb6bc269914f68d2968734d4b678` (`fix(package-2j): complete warning cleanup and closure verification`)
- **RC2 Baseline Ancestor:** `5b489407fdd011ec102f0e46d104e7f0241f99d7`
- **Output Directory:** `scratch/sonnet_project_audit/revised_knowledge_base/`

---

## 1. Document Catalog & Recommended Repository Destinations

| Document | Revised V2 Location (Staging) | Proposed Repository Target | Recommended Adoption Action |
|:---|:---|:---|:---:|
| **1. Executive Audit Report** | `EXECUTIVE_AUDIT_REPORT.md` | `docs/audit/SONNET_55_EXECUTIVE_AUDIT_REPORT.md` | **ADOPT AFTER REVIEW** |
| **2. Detailed Bug Findings** | `DETAILED_BUG_FINDINGS.md` | `docs/quality/DETAILED_BUG_FINDINGS.md` | **ADOPT AFTER REVIEW** |
| **3. Architecture & Risk Analysis** | `ARCHITECTURE_AND_RISK_ANALYSIS.md` | `docs/architecture/ARCHITECTURE_RISK_ANALYSIS.md` | **ADOPT AFTER REVIEW** |
| **4. Test Coverage Gap Analysis** | `TEST_COVERAGE_GAP_ANALYSIS.md` | `docs/quality/TEST_COVERAGE_GAP_ANALYSIS.md` | **ADOPT AFTER REVIEW** |
| **5. AI Agent Guide** | `AI_AGENT_GUIDE.md` | `docs/dev/AI_AGENT_GUIDE.md` | **ADOPT AS SUPPLEMENT** |
| **6. System Map** | `docs/architecture/SYSTEM_MAP.md` | `docs/architecture/SYSTEM_MAP.md` | **ADOPT AFTER REVIEW** |
| **7. Core Invariants** | `docs/architecture/CORE_INVARIANTS.md` | `docs/architecture/CORE_INVARIANTS.md` | **ADOPT AFTER REVIEW** |
| **8. Bug & Risk Register** | `docs/quality/BUG_AND_RISK_REGISTER.md` | `docs/quality/BUG_AND_RISK_REGISTER.md` | **ADOPT AFTER REVIEW** |
| **9. Workflow Skill** | `.agents/skills/.../SKILL.md` | `.agents/skills/godot-project-workflow/SKILL.md` | **ADOPT AFTER REVIEW** |

> **Critical Root Governance Rule:** Root `AGENTS.md` is preserved intact and **MUST NOT BE REPLACED**. `AI_AGENT_GUIDE.md` serves as a derived, additive engineering manual that reinforces root rules while providing tactical guidance on data ownership, preload shadowing, save compatibility, and test verification.

---

## 2. Key Modifications versus Original Sonnet Drafts

1. **Commit References Synchronized:**
   - Updated from pre-commit `1e3a1380e47e55bb83cc592ba5eea13b65660c48` to committed Package 2J HEAD `4a99322a6d2efb6bc269914f68d2968734d4b678`.
2. **GAP-001 Formally Closed:**
   - Original Sonnet audit reported that `world_view.gd` attack-order failure branch had only an untracked scratch verifier.
   - Revised V2 marks GAP-001 as **CLOSED (RESOLVED)**, referencing the tracked suite committed in `4a99322`: `scripts/test/test_world_view_siege_input.gd` (193 lines, 30 checks PASS, Exit Code 0).
3. **RISK-006 Formally Closed:**
   - Original Sonnet audit reported documentation drift (`docs/KNOWN_ISSUES.md` claiming `world_view.gd` was identical to RC2, and `docs/WORKLOG.md` lacking Package 2J closure logs).
   - Revised V2 marks RISK-006 as **CLOSED (RESOLVED)** following the reconciliation and commit in `4a99322`.
4. **RISK-008 Source-Verified:**
   - Performed dedicated verification against `HEAD:scripts/ui/hud.gd` L1167–1186 and `BattleCampaignManager.launch_offensive_campaign()` L805–809. Confirmed that HUD evaluates only execution success (`res["success"]`) and ignores `report.victor`, displaying positive feedback even on defeat. Upgraded to **CONFIRMED STATIC / OPEN**.
5. **Autoload Topology Corrected:**
   - Fully clarified the distinction between the **five engine Autoload Node Singletons** in `project.godot` (`MCPRuntime`, `TimeManager`, `ResourceManager`, `EventManager`, `AudioManager`) and `WorldView`-owned `RefCounted` managers.
6. **Machine-Specific Paths & Stale Variables Removed:**
   - Eliminated hardcoded executable paths (`E:\GODOT ENGINE\...`) and hardcoded branch names from reusable guides, replacing them with generic commands (`godot --headless...`) and repository-relative paths.

---

## 3. Dedicated Source Verification: RISK-008

### 3.1 Code Inspection at Committed HEAD
- **HUD Call Site (`HEAD:scripts/ui/hud.gd` L1174–1186):**
  ```gdscript
  var res: Dictionary = battle_campaign_mgr.call("launch_offensive_campaign", faction_id)
  if not res.get("success", false):
      ...
      show_event_banner("Không Thể Tấn Công", res.get("reason", "Chiến dịch thất bại."), false, 4.0)
      _show_diplomacy_feedback("❌ %s" % res.get("reason", "Không thể tấn công."), true)
  else:
      var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
      if am and am.has_method("play_click"): am.play_click()
      _show_diplomacy_feedback("⚔️ Đã hoàn thành chiến dịch tấn công!", false)
  ```
- **Campaign Resolution (`HEAD:scripts/combat/battle_campaign_manager.gd` L805–809):**
  ```gdscript
  return {
      "success": true,
      "report": report,
      "context": context
  }
  ```

### 3.2 Verification Findings
1. **Meaning of `success`:** In `BattleCampaignManager.launch_offensive_campaign()`, `"success": true` indicates that preflight checks passed, troops were deployed, casualties calculated, and diplomatic penalties applied. It denotes **process execution success**, not military victory.
2. **Outcome Ignored:** The underlying battle report contains `report.victor` (`"attacker"`, `"defender"`, `"draw"`). When the player's force is completely destroyed, `report.victor` is `"defender"`.
3. **Flawed HUD Feedback:** The HUD branch checks only `res.get("success", false)`. It completely ignores `report.victor`. Therefore, when the player loses the battle, the HUD still prints `⚔️ Đã hoàn thành chiến dịch tấn công!` and plays `play_click()`.
4. **Working-Tree vs HEAD Line Offset:** In the uncommitted working tree, an experimental AI M2-B panel toggle (`_toggle_ai_panel()`) was inserted at L938, shifting the HUD method down by +18 lines (L1201 vs L1174). The logic is 100% identical in both.
5. **Final Status:** **CONFIRMED STATIC / OPEN**.

---

## 4. Invariant Verification Status Summary

| Invariant | Domain | Status | Key Evidence / Issue |
|:---|:---|:---:|:---|
| **I-01** | Central Stock Authority | **VERIFIED** | Central stock mutated only via `ResourceManager` APIs. |
| **I-02** | Cost Transactions | **VERIFIED** | Synchronous `reserve_cost()` $\rightarrow$ `commit_cost()` pattern maintained. |
| **I-03** | Resource Conservation | **VIOLATED** | **BUG-001:** Carried goods destroyed when a citizen dies (`citizen_controller.gd` L770). |
| **I-04** | Workplace Buffer Independence | **VERIFIED** | Workplace buffers decoupled from central stock until delivered. |
| **I-05** | Job State Machine | **PARTIAL** | **BUG-002:** Dynamic non-recurring jobs never pruned from `JobManager._jobs`. |
| **I-06** | Citizen Death Idempotency | **VERIFIED** | Protected by `_death_processed` and `deceased_citizen_ids`. |
| **I-07** | Building State Machine | **VERIFIED** | Sequential transitions enforced; unsupported states rejected fail-closed. |
| **I-08** | Equipment Tier Ownership | **VERIFIED** | Tier strictly owned by `PlayerArmyManager` (strict int 1..3). |
| **I-09** | NPC Multiplier Independence | **VERIFIED** | NPC units maintain fixed 1.0 multiplier (`EnemyTacticalUnit._ready()`). |
| **I-10** | Tactical Roster Mirroring | **PARTIAL** | Roster mirrors count, but stationary vs all field units create divergent sets. |
| **I-11** | Field Siege Lifecycle | **VERIFIED** | Clean resolution, active flag clearing, attack-order failure retry preserved. |
| **I-12** | AI Diplomacy Signalling | **VERIFIED** | Actions route through `declare_war()` / `propose_treaty()`, emitting signals. |
| **I-13** | Save Compatibility & Rollback | **VERIFIED** | Fail-closed validation; pre-load snapshotting with recursive rollback. |
| **I-14** | Simulation Calendar Ordering | **VERIFIED** | `hour_passed` before `day_passed`; `ResourceManager` runs before `WorldView`. |
| **I-15** | UI Outcome Truthfulness | **PARTIAL** | Siege failure banner VERIFIED; campaign banner VIOLATED by `RISK-008`. |

---

## 5. Defect, Risk & Gap Reconciliation Summary

- **Bugs:**
  - `BUG-001` (Hauler cargo destroyed on death): **OPEN (CONFIRMED STATIC)**.
  - `BUG-002` (Job accumulation in `_jobs`): **OPEN (PROBABLE)**.
  - `BUG-003` (Autosave overwrites manual save): **OPEN (PROBABLE / PRODUCT INTENT)**.
- **Risks:**
  - `RISK-001`..`RISK-005`, `RISK-007`: **OPEN** (Latent or unverified).
  - `RISK-006` (Docs drift): **CLOSED (RESOLVED in `4a99322`)**.
  - `RISK-008` (HUD campaign banner): **OPEN (CONFIRMED STATIC)**.
- **Test Gaps:**
  - `GAP-001` (Field siege failure test): **CLOSED (RESOLVED in `4a99322`)**.
  - `GAP-002` (Tracked regression runner): **OPEN**.
  - `GAP-003`..`GAP-007`: **OPEN**.
- **Baseline Limitation:**
  - `BASELINE-001` (`TC-ARMY.32`): **CONFIRMED BASELINE LIMITATION** (Inherited from Package 2F; documented in `docs/KNOWN_ISSUES.md`).

---

## 6. Remaining Uncertainties for Project Owner Decision

1. **Autosave Policy (BUG-003):** Does the Owner want a separate slot (`user://saves/autosave.json`) or a setting to adjust autosave frequency?
2. **Faction Elimination (RISK-004):** Should total conquest of outposts trigger `in_exile` or `eliminated` statuses, or is faction destruction reserved for a future phase?
3. **Storage Demolition Policy (RISK-007):** Should demolishing a storehouse with full inventory be blocked if remaining storage cannot accommodate the goods, or should current behavior (allowing over-capacity inventory) persist?

---

## 7. Final Adoption Recommendation

The revised package under `scratch/sonnet_project_audit/revised_knowledge_base/` has been verified for complete internal consistency and alignment with committed HEAD `4a99322`.

**Recommended Action for Project Owner:**
1. Approve adoption of the files to their proposed repository destinations (`docs/architecture/`, `docs/quality/`, `docs/dev/`, `.agents/skills/`).
2. Maintain root `AGENTS.md` unchanged.
3. Queue `BUG-001` and `RISK-008` for resolution in the next development slice prior to Package 2K.
