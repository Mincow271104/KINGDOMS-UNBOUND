# ARCHITECTURE AND RISK ANALYSIS — KINGDOMS UNBOUND (REVISED V2)

- **Date:** 2026-11-07 · **Committed Baseline HEAD:** `4a99322a6d2efb6bc269914f68d2968734d4b678`
- **Methodology:** Static architecture analysis and call-graph verification across Godot 4.7-stable codebase.

---

## 1. System Topology & Composition Model

### 1.1 Five Engine Autoload Singletons
`project.godot` registers exactly five Node singletons:
1. `MCPRuntime` (`addons/godot_mcp/runtime/mcp_runtime.gd`): Tooling / Addon runtime.
2. `TimeManager` (`scripts/core/time_manager.gd`): Calendar, speed scaling, hourly/daily signal dispatcher.
3. `ResourceManager` (`scripts/economy/resource_manager.gd`): Central stock ledger, capacity enforcement, daily food upkeep.
4. `EventManager` (`scripts/core/event_manager.gd`): Global signal router and event history buffer.
5. `AudioManager` (`scripts/audio/audio_manager.gd`): Procedural 16-bit audio waveform generator and SFX player pool.

### 1.2 `WorldView` as Composition Root and Central Orchestrator
Every other manager in the game is a **non-autoload `RefCounted` instance** created and owned by `WorldView` (`scripts/world/world_view.gd`, 2478 lines) during `_generate_and_build_world()`:
- `JobManager`, `WorkplaceManager`, `AutomationManager`, `ResearchManager`, `FogOfWar`, `POIManager`, `WorldEventSystem`, `FactionManager`, `ImmigrationManager`, `VictoryManager`, `BattleCampaignManager`, `PlayerArmyManager`, `TacticalMilitaryManager`, `EnemyMilitaryManager`, `FieldSiegeManager`, `WorldData`, and `GridNavigation`.
- **Architectural Characteristic:** `WorldView` acts as both the Composition Root and the central orchestrator (input handling, visual presentation, day/hour orchestration, workplace sync, autosave).
- **Coupling Style:** Heavy reliance on duck-typed calls (`has_method()`, `.call()`, `.get()`) alongside dependency injection setters (`set_tactical_military_manager()`, `set_field_siege_manager()`). This facilitates headless testing but means renames or signature mismatches fail at runtime rather than parse time.

---

## 2. Data Ownership Assessment (Single Source of Truth)

| Domain | Authoritative Owner | Architecture Verdict | Critical Notes |
|:---|:---|:---:|:---|
| **Central Stock & Capacities** | `ResourceManager` | **Healthy** | All modifications go through reserve $\rightarrow$ commit or atomic credits. |
| **Workplace Buffers vs Central Stock** | `WorkplaceManager` (`_workplaces[ch_id]["buffer_amount"]`) | **Healthy (except Bug-001)** | Output buffers are completely decoupled from central stock until delivered by a hauler. Carrier cargo is destroyed on death (`BUG-001`). |
| **Equipment Tier Authority** | `PlayerArmyManager` (`equipment_tier`) | **Healthy** | Tier is strictly 1..3, owned solely by `PlayerArmyManager`. Units query tier multipliers dynamically; tier is never stored in tactical unit state. |
| **Strategic Army vs Tactical Units** | Dual Representation: `PlayerArmyManager` and `TacticalMilitaryManager` | **Partially Fragile** | Synchronized via `sync_with_player_army()`. Stationarity and rally perimeter rules create distinct operational sets (`get_field_units()` vs `get_all_field_units()`). |
| **Siege State & Objectives** | `FieldSiegeManager` (`objectives`, `active_sieges`) | **Healthy Lifecycle; Monotonic Growth** | Clean resolution and retry idempotency, but resolved records are never pruned from `active_sieges` (`RISK-002`). |
| **Factions & Relations** | `FactionManager` (`_factions`, `_pairwise_relations`) | **Healthy** | Pure strategy planners; all diplomacy actions route through signalling APIs. |
| **Jobs & Worker Assignment** | `JobManager` (`_jobs`) | **Healthy State Machine; Memory Growth** | Clean state machine, but dynamic non-recurring jobs accumulate without pruning (`BUG-002`). |

---

## 3. Event Ordering, Signals & Re-Entrancy

1. **Day Boundary Execution Chain:**
   - `TimeManager._advance_one_hour()` detects day rollover $\rightarrow$ emits `hour_passed` $\rightarrow$ emits `season_changed`/`year_passed` (if applicable) $\rightarrow$ emits `day_passed`.
   - **Subscriber Order (Connection Sequence):**
     1. `ResourceManager._on_day_passed`: Connected first via engine autoload initialization $\rightarrow$ processes food consumption and tally rotation.
     2. `HUD._on_day_passed`: Updates UI calendar.
     3. `WorldView._on_simulation_day_passed`: Sequentially executes:
        - `WorldEventSystem.update_daily_modifiers(day)` & event check.
        - `FactionManager.update_daily_simulation(day)`.
        - `PlayerArmyManager.process_daily_upkeep(day)`.
        - `BattleCampaignManager.process_daily_raids(day)`.
        - Trade caravan arrivals / departures.
        - `SaveManager.save_to_file(self)` (daily autosave).
2. **Hourly Execution Chain:**
   - `WorldView._on_simulation_hour_passed` advances research, refreshes vision/Fog of War, updates POI proximity rewards, runs logistics haul creation (`update_hauling_jobs`), evaluates automation rules (`automation_mgr.evaluate_rules`), checks immigration, and ticks victory/crisis stability.
   - Concurrently, living `CitizenController` instances receive `hour_passed` to update hunger, fatigue, and health.
3. **Per-Frame Processing:**
   - Military units advance movement via real-time `delta * speed`, independent of `TimeManager` simulation hours.
   - `WorldView._process()` polls all active sieges via `field_siege_mgr.evaluate_siege_status()`.

---

## 4. Determinism & Timing Considerations

- **Campaign & Raid Determinism:** Seeds are generated deterministically using `hash(str(world_seed) + "_" + str(day) + "_" + target_faction_id + "_" + str(seq))`. This ensures repeatable abstract battle resolutions within the same engine version.
- **Combat Movement vs Simulation Clock:** Because tactical movement uses frame `delta * speed` while simulation ticks use an hourly accumulator, micro-combat positioning can vary slightly depending on framerate, though macro battle calculations (`BattleResolver`) remain purely deterministic.
- **Clock Rollover Resiliency:** `TimeManager._process` preserves residual sub-hour accumulators across speed changes and frame spikes, preventing simulation drift.

---

## 5. Top Architectural & Operational Risks (Ranked)

1. **Verification Fragility & Lack of Tracked Runner (`GAP-002`):**
   No tracked regression runner exists in `scripts/test/`. Existing untracked scratch runners parse output using regex word counting rather than process exit codes.
2. **Resource Conservation Hole on Citizen Death (`BUG-001`):**
   Carried goods ($\le 10$ units) vanish when a citizen dies, violating Invariant I-03 during famine.
3. **Monotonic Job Array Growth (`BUG-002`):**
   Completed hauling jobs remain in `JobManager._jobs` forever, resulting in $O(N)$ scan overhead in long-running games.
4. **Save Slot Collision (`BUG-003`):**
   Daily autosave targets `world_save.json`, overwriting the manual save checkpoint.
5. **HUD Campaign Feedback Inaccuracy (`RISK-008`):**
   `HUD.attack_faction()` reports success upon campaign resolution regardless of whether the player's force was victorious or eliminated.
6. **God-Object Blast Radius:**
   Edits to `world_view.gd` affect virtually every subsystem. Changes must remain surgical and verified through dedicated headless tests.

---

## 6. Healthy Subsystems vs Unexamined Areas

- **Healthy Subsystems:** Central resource ledger, equipment upgrade transactions, save schema validation and rollback recovery, siege state machine, AI diplomacy signalling, calendar mathematics, and Package 2J attack-order failure banner handling.
- **Unexamined / Partially Examined Areas:** Full HUD codebase (~2900 lines), automation editor UI, legacy profile point accumulation edge cases, navigation mesh corner-cases, audio waveform buffer edge cases, and frame-rate dependence of real-time tactical skirmishes.
