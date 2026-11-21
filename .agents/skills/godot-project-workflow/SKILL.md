---
name: godot-project-workflow
description: Step-by-step workflow for implementing, fixing, or verifying changes in KINGDOMS UNBOUND (Godot 4.7). Use for any code change, bug fix, test authoring, audit, or commit-readiness review in this repository.
---

# Godot Project Workflow — Kingdoms Unbound (Revised V2)

> **Standard Engineering Workflow & Verification Checklist.**
> Paths and commands are relative to the repository root.

---

## 1. Inspect Scope & Authorization

1. Restate the task boundaries in one paragraph: allowed files, forbidden files, and the current phase gate.
2. If requirements or scope boundaries are ambiguous, ask for clarification before editing code.
3. **Hard Constraint:** Work only on the currently authorized phase. Never combine phases or begin subsequent package implementation prematurely.

---

## 2. Repository Preflight & Working-Tree Protection

Execute the mandatory preflight sequence before touching disk:
```powershell
git branch --show-current
git rev-parse HEAD
git status --short
git diff --stat
git diff --check
```
- **Record Working-Tree State:** Catalog all existing modified and untracked files before starting.
- **Frozen Prototype Isolation:** Experimental prototypes (such as AI M2-B files under `scripts/ai/`, `scenes/ui/ai_command_panel.*`, `scripts/ui/ai_command_panel.*`, `scripts/test/test_ai_*`, and HUD integration hooks) are frozen. Never modify, stage, or commit AI prototype files during core gameplay packages.
- **Prohibitions:** Never run `git reset --hard`, `git clean -fd`, or `git stash`.

---

## 3. Consult Architectural Knowledge & Registers

1. Read `docs/architecture/SYSTEM_MAP.md` to identify the authoritative owner of the target data.
2. Read `docs/architecture/CORE_INVARIANTS.md` to review the non-negotiable rules governing the subsystem.
3. Consult `docs/quality/BUG_AND_RISK_REGISTER.md` and `docs/KNOWN_ISSUES.md` to ensure the issue is not a documented baseline limitation (e.g., `TC-ARMY.32`).
4. Read the **tail (last 100–150 lines)** of `docs/WORKLOG.md` for current phase context.

---

## 4. Trace Production Call Paths

1. Use `Select-String` / grep to trace all production callers, callees, signals, and test call sites.
2. Map:
   - Authoritative state owner (e.g., `ResourceManager` vs `WorkplaceManager`).
   - Signal execution order at hour and day rollovers.
   - Save/load serialization and deserialization touch points.
3. Verify claims against actual source code; never assume previous reports were complete or correct.

---

## 5. Plan Minimal Reversible Changes

1. List the exact target files and functions.
2. Evaluate constraints:
   - **Save Schema:** Never change the schema without backward-compatible migrations.
   - **Resource Ledgers:** Ensure cost deductions follow synchronous `reserve_cost()` $\rightarrow$ `commit_cost()`.
   - **Determinism:** Ensure RNG seeds and calendar progression remain stable.
3. Fix issues at the authoritative owner, not via fragile caller-side workarounds.

---

## 6. Implement Surgical Changes

1. Make small, focused, reversible edits.
2. Maintain existing public method signatures.
3. Preserve unrelated comments, docstrings, and formatting.
4. Return consistent `{success: bool, reason: String}` dictionaries for UI actions.
5. **Preload Hygiene:** Never declare `const X = preload(...)` where `X` matches a global `class_name`.

---

## 7. Author Committed Regression Tests

1. Every fix or feature must include a **committed test suite** in `scripts/test/` (extending `SceneTree`).
2. Cover both success and failure paths, boundary conditions, and idempotency.
3. Use isolated temporary save paths (`SaveManager.set_test_default_save_path()`); never touch `user://saves/world_save.json`.
4. Output a single final summary line and call `quit(0)` for PASS or `quit(1)` for FAIL.

---

## 8. Execute Validation & Verification

1. Run targeted headless test suites using the Godot CLI:
   ```powershell
   godot --headless -s res://scripts/test/<test_suite>.gd
   ```
2. **Tracked Regression Runner (GAP-002):** Execute the authoritative headless regression runner across all tracked suites:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/test/run_regression.ps1
   # Or run a targeted suite:
   powershell -ExecutionPolicy Bypass -File scripts/test/run_regression.ps1 -Suite <suite_name>
   ```
3. **Evaluate by Exit Code:** Check the raw process exit code (`$LASTEXITCODE` in PowerShell). Never rely on heuristic regex scripts that count `"PASS"` / `"FAIL"` words.
4. **All-Scripts Compilation Check (GAP-006):** Run `scripts/test/test_all_scripts_load.gd` to verify all 124 `.gd` files compile and load headlessly without symbol shadowing.
5. **Baseline Limitation Honesty:** If `test_player_army.gd` fails on `TC-ARMY.32`, verify that it is the exact known baseline failure (`ISSUE-006`). The runner automatically classifies this as `EXPECTED_BASELINE_FAILURE`. Never obscure or silently alter baseline tests.

---

## 9. Inspect Staged vs Unstaged Diffs

1. Run:
   ```powershell
   git status --short
   git diff --stat
   git diff --check
   ```
2. Confirm that uncommitted prototype files, temporary logs, screenshots, and `.uid` metadata remain uncommitted and unstaged.
3. **Never use broad staging:** `git add .` and `git add -A` are strictly prohibited. Stage only via explicit file paths.

---

## 10. Independent Verification Checkpoint (Mandatory Pre-Commit Gate)

Perform this self-review before proposing any commit:
- [ ] **Scope Alignment:** Every modified line maps directly to authorized requirements; zero unrelated refactoring.
- [ ] **Observed Command Evidence:** Every claim in the report is backed by an observed command output and exit code.
- [ ] **Committed Test:** A committed regression test exists under `scripts/test/` (not just in `scratch/`).
- [ ] **Core Invariants Preserved:** `docs/architecture/CORE_INVARIANTS.md` re-read; no invariant weakened.
- [ ] **Save Compatibility:** Save/load round-trip verified; legacy saves load cleanly fail-closed.
- [ ] **Exit Code Verification:** Test passes verified via process exit code 0, not word-grep tallies.
- [ ] **Documentation Synchronized:** `docs/WORKLOG.md` and defect registers updated; stale references corrected.
- [ ] **Explicit Authorization Required:** Propose the exact file allowlist; **never commit or push automatically**.

---

## 11. Truthful Completion Report

Conclude every task with a structured markdown report:
- **Files Created / Modified:** Clickable links with forward slashes.
- **Requirements Covered & Features Completed.**
- **Validation Results:** Specific commands, exit codes, and assertion tallies.
- **Evidence Level Distinction:** State clearly whether tests were *Unit*, *Integration*, *Visual*, or *Manual Acceptance*.
- **Known Limitations & Outstanding Issues.**
- **Git Status:** Full `git status --short` output and exact next step.
