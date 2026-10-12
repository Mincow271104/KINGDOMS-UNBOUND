# KINGDOMS UNBOUND — User-Visible Changelog

All notable changes to the Kingdoms Unbound project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### [0.2.0] - 2026-10-12
#### Added
- Phase 1 Vertical Slice & Visual-Validation Gate completed:
  - Coordinate decoupling utility `scripts/utils/iso_math.gd` with 2:1 dimetric isometric forward/inverse math.
  - Automated coordinate unit test `scripts/test/test_coordinates.gd` (TC-1.1 passed).
  - Authoritative simulation clock `scripts/core/time_manager.gd` with pause safety, speeds (0x–3x), and calendar.
  - Automated TimeManager unit test `scripts/test/test_time_manager.gd` (TC-1.4 passed).
  - Procedural pixel-art asset generator `scripts/tools/generate_pixel_assets.gd` generating 13 assets adhering strictly to `docs/ASSET_STYLE_GUIDE.md` and 27-color palette.
  - Deterministic procedural world generator `scripts/world/world_generator.gd` generating 64×64 simulation grid.
  - Automated world generator reproducibility test `scripts/test/test_world_gen.gd` (TC-1.2 passed).
  - Dedicated Visual-Validation Gate scene `scenes/test/visual_validation_test.tscn` demonstrating terrain, props, building with visible rooftop/facade, moving citizen, diamond cursor hover, and flawless Y-sorting.
  - In-Game HUD `scenes/ui/hud.tscn` with time controls, clock, resource ledger, and pause menu.
  - 64×64 Full World View `scenes/world/world_view.tscn` with starter buildings and 24 citizens.
  - Main Menu `scenes/ui/main_menu.tscn` with New World (seed, difficulty), Settings, and Quit.
  - Configured `run/main_scene` in `project.godot`.
#### Added
- Formalized comprehensive project specification suite:
  - `docs/SCOPE_DECISIONS.md` resolving all GDD design ambiguities and starter resource allocations.
  - `docs/GAME_RULES.md` specifying 2:1 dimetric isometric coordinate formulas, simulation tick schedules, needs decay rates, and victory/collapse conditions.
  - `docs/ARCHITECTURE.md` establishing strict separation between 64×64 logical simulation and presentation layers.
  - `docs/IMPLEMENTATION_PLAN.md` defining phased execution roadmap across 10 technical phases.
  - `docs/TEST_PLAN.md` establishing headless command-line and Godot MCP verification suites.
  - `docs/BACKLOG.md` detailing prioritized tasks and dependency chains.
  - `docs/KNOWN_ISSUES.md` recording technical diagnostic solutions.
- Added `docs/.gdignore` to cleanly isolate documentation from Godot's asset importer.
- Configured `MCPRuntime` autoload singleton in `project.godot`.
- Verified live Godot MCP bridge connection on port 6505.
