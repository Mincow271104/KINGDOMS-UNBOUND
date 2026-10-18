# KINGDOMS UNBOUND — Known Issues & Technical Resolutions

## Active Issues

### ISSUE-005: Real-Time Tactical Combat and Army Pathfinding Deferred to Future Milestones
- **Severity:** Low / Architectural Scope Boundary (By Design for Package 1K)
- **Symptom:** Combat resolution occurs as an authoritative abstract turn/tick calculation rather than real-time physical unit movement across the isometric grid.
- **Root Cause:** By design per GDD Section 10.4 and MASTER_PROMPT constraints, combat is modeled through deterministic multi-factor formulas (`BattleResolver.resolve_settlement_battle`) rather than RTS tactical combat.
- **Resolution / Scope:** Package 1K closed the live gameplay loop by implementing `BattleCampaignManager`, providing scheduled raids, living guard defense, deterministic casualties, and resource plunder. Physical army marching sprites, tactical field maneuvering, and manual siege controls remain deferred to post-MVP tactical combat milestones.

---

## Resolved Issues

### ISSUE-004: Live Production Settlement Battle Trigger (Resolved in Package 1K)
- **Severity:** Low / Architecture Scope Boundary
- **Symptom:** `BattleResolver.resolve_settlement_battle` was previously not hooked into the live game loop upon war declaration.
- **Resolution:** Implemented `BattleCampaignManager` (`scripts/combat/battle_campaign_manager.gd`), wiring `FactionManager.war_declared` to schedule incoming settlement raids (3-day initial delay, 5-day recurring interval), querying living guards gated by active Barracks, applying casualties deterministically, plundering resources, and persisting state across saves. Verified with 14 automated tests in `scripts/test/test_live_battle_loop.gd`.

### ISSUE-001: Godot Editor Did Not Auto-Connect MCP Bridge on Direct Executable Launch
- **Severity:** Medium
- **Symptom:** `get_godot_status` reported `connected: false` even though Godot process was running.
- **Root Cause:** Launching `Godot_v4.7-stable_win64.exe` without command-line arguments opens Godot's Project Manager, not the game project. In Project Manager mode, project plugins (including `godot_mcp`) are not loaded.
- **Resolution:** Launch Godot editor targeting the project directory:
  ```powershell
  & "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" -e --path "E:\KINGDOMS UNBOUND\kingdoms-unbound"
  ```
- **Verification:** MCP bridge connected successfully on port 6505, confirmed via `get_godot_status` and `diagnose_connection`.

### ISSUE-002: Corrupt PNG Import Warning on `kingdom_visual_reference.png`
- **Severity:** Low
- **Symptom:** Godot scanner reported `WARNING: Not a PNG file` / `ERR_FILE_CORRUPT` for `res://docs/reference/kingdom_visual_reference.png`.
- **Root Cause:** The reference image was encoded as JPEG (JFIF format `FF D8 FF E0`), but named with a `.png` extension inside the project root, triggering Godot's asset importer.
- **Resolution:** Added `docs/.gdignore` so Godot ignores the documentation folder entirely. Deleted the invalid `kingdom_visual_reference.png.import` artifact.
- **Verification:** Godot headless project scan completed with zero errors and zero warnings.

### ISSUE-003: "No main scene defined in project" Exit Code
- **Severity:** Expected Behavior (Phase 0)
- **Symptom:** Running the project executable directly without a scene argument exits with error "Can't run project: no main scene defined".
- **Status:** Expected during Phase 0 prior to creating `MainMenu.tscn` / `WorldView.tscn` in Phase 1.
- **Resolution:** Main scene will be assigned to `res://scenes/ui/main_menu.tscn` during Phase 1 Task 1.9.
