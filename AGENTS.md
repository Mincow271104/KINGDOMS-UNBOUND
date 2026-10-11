# Kingdoms Unbound — Workspace Rules

## 1. Authoritative Documents
- `MASTER_PROMPT.md` defines the AI's development responsibilities, non-negotiable constraints, ambiguity resolutions, phase workflow, and exit gates.
- `docs/GDD.md` is the authoritative source for game design, mechanics, simulation rules, and gameplay requirements.
- Read both documents before beginning an implementation session.
- Never silently override requirements or invent undocumented mechanics. Record unresolved conflicts and report them.

## 2. Phase-Gated Development
- Follow the phases and exit gates defined in `MASTER_PROMPT.md`.
- Work only on the currently authorized phase.
- Do not skip gates, combine phases for convenience, or begin later-phase implementation prematurely.
- Complete the required validation and report pass/fail results before declaring a phase complete.

## 3. Protect the Existing Project
- Work only within the established project root.
- Preserve the existing Godot version, project settings, architecture, and Git history unless a change is explicitly required and justified.
- Treat `addons/godot_mcp/` as third-party tooling; do not modify it unless necessary and clearly justified.
- Never perform destructive Git operations, force-push, delete project assets, or overwrite unrelated work without explicit authorization.
- Never expose or commit credentials, API keys, or secrets.

## 4. Incremental Implementation
- Inspect existing files and dependencies before editing.
- Make small, focused, reversible changes rather than generating the entire game in one pass.
- Reuse existing systems and resources when appropriate. Avoid unnecessary dependencies, duplicate systems, speculative abstractions, and unrelated refactors.
- Keep files organized consistently with Godot conventions.

## 5. Testing and Evidence
- Use Godot MCP only after confirming it is connected to the intended project.
- Use Godot 4.7-compatible validation and testing methods.
- Run relevant script checks, headless project checks, and runtime tests as applicable to the current phase.
- Distinguish tools that are available from tests that were actually executed successfully.
- Never claim a test passed unless its result was observed.
- If a test cannot be executed, report the limitation and its impact.

## 6. Completion Reports
After each implementation task, report:
- Files created or modified.
- Features completed and requirements covered.
- Validation and test results.
- Known issues and unresolved decisions.
- Git status and any remaining phase-gate requirements.

Do not commit, push, or proceed to another phase automatically unless authorized by the project workflow.