# KINGDOMS UNBOUND — Known Issues & Technical Resolutions

## Active Issues
*None currently blocking development.*

---

## Resolved Issues

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
