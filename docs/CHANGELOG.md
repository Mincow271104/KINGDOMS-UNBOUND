# KINGDOMS UNBOUND — User-Visible Changelog

All notable changes to the Kingdoms Unbound project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### [0.1.0] - 2026-10-12
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
