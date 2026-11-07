# KINGDOMS UNBOUND — AI AGENT DEVELOPMENT & ENGINEERING GUIDE (V2)

> **Important Governance Note:** This document is an additive, operational engineering guide for AI coding assistants working in the Kingdoms Unbound codebase. It **supplements but does NOT replace** the authoritative root `AGENTS.md` and `MASTER_PROMPT.md`.

---

## 1. Project Identity & Architecture Baseline

- **Engine:** Godot 4.7-stable (GDScript, Forward+, Jolt Physics 3D).
- **Architecture Model:** Dimetric Isometric 64×64 simulation. Central composition root is `WorldView` (`scripts/world/world_view.gd`), orchestrating non-autoload `RefCounted` managers alongside exactly five engine Autoload singletons (`MCPRuntime`, `TimeManager`, `ResourceManager`, `EventManager`, `AudioManager`).
- **Language Convention:** Code identifiers, internal symbols, and variable names are English. Player-facing strings, UI feedback, and historical project documentation are primarily Vietnamese.

---

## 2. Document Hierarchy & Strategic Reading Order

When beginning or resuming a task, follow this strict reading hierarchy. Do not read large historical logs in their entirety:
1. **Authoritative Governance (Highest Priority):**
   - Root `AGENTS.md` (Workspace Rules & Non-Negotiable Constraints).
   - `MASTER_PROMPT.md` (AI development responsibilities, phase workflow, and exit gates).
   - `docs/GDD.md` (Game design, simulation rules, and mechanics authority).
2. **Architecture & Invariants Reference:**
   - `docs/architecture/SYSTEM_MAP.md` (Data ownership and signal sequence map).
   - `docs/architecture/CORE_INVARIANTS.md` (15 non-negotiable simulation invariants).
3. **Quality & Defect Registers:**
   - `docs/quality/BUG_AND_RISK_REGISTER.md` (Catalog of known bugs, risks, and test gaps).
   - `docs/KNOWN_ISSUES.md` (Documented baseline limitations, including `ISSUE-006` / `TC-ARMY.32`).
4. **Current Phase Context & Next Step:**
   - Read the **tail (last 100–150 lines)** of `docs/WORKLOG.md`. **Never read `docs/WORKLOG.md` in full** (file size is $>840\text{ KB}$ and will unnecessarily exhaust context windows).
   - Query `docs/SCOPE_DECISIONS.md` via targeted text search for specific feature boundaries.

---

## 3. Mandatory Preflight & Workspace Safety

Before making any changes or running tests:
1. **Preflight Commands:**
   ```powershell
   git branch --show-current
   git rev-parse HEAD
   git status --short
   git diff --stat
   git diff --check
   ```
2. **Working-Tree Protection:**
   - Inspect existing uncommitted files. Do not assume uncommitted files are accidental.
   - **Strict AI Prototype Isolation:** Experimental AI work (e.g., AI M2-B prototype files: `scripts/ai/`, `scenes/ui/ai_command_panel.*`, `scripts/ui/ai_command_panel.*`, `scripts/test/test_ai_*`, AI UI integrations in `hud.gd`/`hud.tscn`, and AI entries in `docs/WORKLOG.md`) is completely frozen and separated from core gameplay packages. Never stage, commit, or modify AI prototype files during core gameplay tasks.
   - **Protected Engine Settings:** Never stage or commit unintended changes to `project.godot` (such as editor-generated display settings drops).

---

## 4. Hard Prohibitions & Non-Negotiable Constraints

- **No Destructive Git Operations:** Never execute `git reset --hard`, `git clean -fd`, `git stash drop`, or force-push.
- **No Unauthorized Commit or Push:** Never commit, push to remote `origin`, create PRs, or switch branches unless explicitly authorized by the Project Owner.
- **No Premature Phase Advancement:** Work strictly within the currently authorized phase. Never skip exit gates or combine phases for convenience.
- **No Broad Staging:** Never run `git add .` or `git add -A`. All staging must use explicit path allowlists.
- **No Direct Modification of Player Saves:** Never overwrite or mutate active player saves in `user://saves/world_save.json`. Tests must use isolated temporary paths or mock saves.
- **Protect Third-Party Tooling:** Treat `addons/godot_mcp/` as third-party infrastructure. Do not edit unless strictly necessary and authorized.

---

## 5. Engineering Standards & Coding Rules

1. **Incremental Implementation:**
   - Inspect callers and callees across the entire call-graph before editing.
   - Make small, focused, reversible changes. Avoid speculative abstractions or unrelated refactors.
   - Preserve existing unrelated comments, docstrings, and formatting.
2. **Economic & Resource Transactions:**
   - `ResourceManager` is the sole authority for central stock. Never mutate `_current_stock` directly outside authorized serialization.
   - Cost deductions must execute synchronously as `reserve_cost()` followed immediately by `commit_cost()`. Multi-resource refunds must use `add_resources_atomic()`.
3. **Save Compatibility & Fail-Closed Loading:**
   - Never alter the save schema without maintaining backward-compatible migration paths for legacy saves.
   - `SaveManager.validate_save_data()` must reject invalid types and out-of-range values fail-closed before any world mutations occur.
4. **GDScript Preload Shadowing Hygiene:**
   - Never declare constants using `const X = preload(...)` where `X` matches a global `class_name` registered in ClassDB (this triggers compile-time circular parse errors). Use unique suffixes (e.g., `const WorldGeneratorScript = preload(...)`).
5. **Truthful UI Result Feedback:**
   - Player-facing UI banners must reflect actual simulation outcomes. Never display success feedback if the underlying manager returned failure or if a battle was lost.

---

## 6. Testing, Regression & Evidence Standards

1. **Test Execution Command:**
   Run headless suites using the generic Godot CLI:
   ```powershell
   godot --headless -s res://scripts/test/<test_suite>.gd
   ```
2. **Exit Code Standard:**
   - Always evaluate test success based on **process exit codes (`0` for PASS, non-zero for FAIL)** and the suite's printed summary line.
   - **Never trust heuristic regex word-counting scripts** that grep for `"PASS"` or `"FAIL"`, as these produce false negatives when encountering assertions like `"fail-closed"`.
3. **Committed Test Requirement:**
   - Every bug fix or new feature must include a **committed regression test** under `scripts/test/`. Never leave verification proof only in temporary scratch scripts.
4. **Reporting Evidence Categories:**
   Clearly distinguish the evidence level in completion reports:
   - *Unit Test (Headless)*: Verifies isolated manager math/state.
   - *Integration Test (Headless Scene)*: Verifies full scene wiring and synthetic input.
   - *Automated Visual/GUI Harness*: Verifies off-screen rendering and screenshots.
   - *Natural Unassisted Gameplay Acceptance*: Manual interactive gameplay evaluation.
5. **Known Baseline Failure Reporting:**
   Always report `TC-ARMY.32` in `test_player_army.gd` as an existing baseline limitation (`ISSUE-006`). Never report it as a new failure or attempt to silence it by weakening test assertions.

---

## 7. Interruption Recovery & Completion Discipline

1. **Quota / Interruption Handling:**
   If an interruption or quota exhaustion warning occurs, immediately stop starting new tasks. Finish the smallest safe atomic operation, save the state to disk, document unfinished work in `docs/WORKLOG.md`, and report current status.
2. **Task Completion Report Requirements:**
   Every task report must conclude with:
   - Files created or modified (with clickable file links).
   - Features completed and requirements verified.
   - Validation and test results (specifying commands, exit codes, and assertion tallies).
   - Known issues and unresolved decisions.
   - Git status (`git status --short`) and exact next step.
