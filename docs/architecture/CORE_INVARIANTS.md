# CORE SIMULATION INVARIANTS — KINGDOMS UNBOUND (REVISED V2)

> **Last Verified:** 2026-11-07 against committed Baseline HEAD `4a99322a6d2efb6bc269914f68d2968734d4b678`.
> Status Legend:
> - **VERIFIED:** Verified in committed source and backed by test evidence.
> - **PARTIAL:** Validated in core state machine, but contains documented architectural gaps or divergent semantics.
> - **VIOLATED:** Known active violation in production source code (mapped to BUG ID).

---

### I-01: `ResourceManager` is the sole authority for central stock — VERIFIED
- **Rule:** All modifications to central resource stock, reservations, and storage capacities must route through public `ResourceManager` APIs. Outside authorized save deserialization (`SaveManager.apply_loaded_state_to_world` after `reset_economy`), code must never mutate `_current_stock` or `_capacities` directly.
- **Source Files & Functions:** `scripts/economy/resource_manager.gd` (`reserve_cost`, `commit_cost`, `release_cost`, `add_resource`, `add_resources_atomic`, `consume_resource`).
- **Callers:** `WorkplaceManager`, `BuildingSystem`, `PlayerArmyManager`, `BattleCampaignManager`, `FieldSiegeManager`.
- **Related IDs:** `RISK-001`.

---

### I-02: Cost transactions must be `reserve` $\rightarrow$ `commit` in one synchronous call — VERIFIED
- **Rule:** Resource deduction must begin with an all-or-nothing `reserve_cost(cost)`, followed immediately and synchronously by `commit_cost(cost)` (or `release_cost(cost)` on abort). Because `commit_cost()` does not validate previous reservations and clamps at 0 (`RISK-001`), unreserved commits are strictly forbidden. Multi-resource credits requiring atomicity must use `add_resources_atomic()`.
- **Source Files & Functions:** `scripts/economy/resource_manager.gd` L117–145; `scripts/military/player_army_manager.gd` L368–378; `scripts/economy/workplace_manager.gd` L201–203.
- **Related IDs:** `RISK-001`.

---

### I-03: No silent resource loss across buffers, carriers, and storage — **VERIFIED**
- **Rule:** Resources must be strictly conserved across transitions: Workplace Output Buffer $\rightarrow$ Hauler Cargo (`carrying_*`) $\rightarrow$ Central Stock (`ResourceManager`). If a delivery destination is blocked, cargo must return to the source buffer; if central storage is full, the hauler must retain the remainder.
- **Resolution (BUG-001):** When a citizen carrying resources dies, `CitizenController.die()` calls `recover_cargo(target_rm)` to deposit carried cargo into central storage via `ResourceManager.add_resource()`. In addition, `WorldView._on_citizen_died()` executes a fail-closed recovery check prior to freeing the node; any cargo rejected due to storage saturation is durably retained in `WorldView.pending_death_cargo` and flushed into storage once space opens. Verified across 12 scenarios in `scripts/test/test_hauler_death_cargo_conservation.gd`.
- **Source Files & Functions:** `scripts/entities/citizen_controller.gd` (`recover_cargo`, `die`); `scripts/world/world_view.gd` (`_on_citizen_died`, `add_pending_death_cargo`, `flush_pending_death_cargo`); `scripts/persistence/save_manager.gd`.
- **Related IDs:** `BUG-001` (CLOSED), `GAP-003`.

---

### I-04: Workplace output buffer $\neq$ Central stock — VERIFIED
- **Rule:** Production cycles increment only `WorkplaceData.buffer_amount` (bounded by buffer capacity). Central stock increases only when a hauler successfully executes a delivery deposit (`_deposit_hauler_cargo()`). Workplaces requiring input recipes consume inputs from central stock via reserve $\rightarrow$ commit at the moment of production, provided output buffer space exists.
- **Source Files & Functions:** `scripts/economy/workplace_manager.gd` L172–223; `scripts/entities/citizen_controller.gd` L372–468.
- **Related IDs:** `BUG-001`.

---

### I-05: Job state machine lifecycle — **VERIFIED**
- **Rule:** Jobs transition strictly: `AVAILABLE` $\rightarrow$ `RESERVED` (upon `request_job`) $\rightarrow$ `IN_PROGRESS` $\rightarrow$ `COMPLETED` (or back to `AVAILABLE` for recurring jobs). Blocked paths, worker death, and role changes must call `release_job()`. Starter recurring jobs (`farm_starter`, `woodcutter_starter`) survive save loads.
- **Pruning & Bounded Lifecycle (BUG-002):** Terminal dynamic non-recurring jobs (`is_recurring = false`) that transition to `COMPLETED` or `CANCELLED` are pruned immediately from the active `_jobs` registry, while recurring jobs loop cleanly back to `AVAILABLE`. A bounded ring buffer (`_terminal_jobs_history`, size $\le 50$) retains recent history for diagnostics without memory bloat. Verified across 10 scenarios in `scripts/test/test_job_lifecycle_pruning.gd` (including 1,000-cycle stress test).
- **Source Files & Functions:** `scripts/jobs/job_manager.gd` L275–365; `scripts/entities/citizen_controller.gd`.
- **Related IDs:** `BUG-002` (CLOSED), `GAP-003`.

---

### I-06: Citizen death handling is idempotent — VERIFIED
- **Rule:** `CitizenController.die()` and `WorldView._on_citizen_died()` must be idempotent. Re-triggering death on an already-deceased citizen must not emit duplicate events, cause double-removals, or corrupt population counts.
- **Source Files & Functions:** `scripts/entities/citizen_controller.gd` L776–799 (`_death_processed` guard); `scripts/world/world_view.gd` L570–578 (`deceased_citizen_ids` index check).
- **Related IDs:** `BUG-001`.

---

### I-07: Building state machine & operational transitions — VERIFIED
- **Rule:** Buildings progress: `under_construction` $\rightarrow$ `active`; `paused` is permitted only for pausable operational types (farm, woodcutter, quarry, mine, workshop). Demolition is strictly forbidden while under construction, upgrading, or destroyed. Demolition refunds are credited via `add_resources_atomic()`. Unsupported states (such as `"damaged"`) are rejected fail-closed.
- **Source Files & Functions:** `scripts/economy/building_system.gd` L420–475; `scripts/world/world_view.gd` L1897–1906.
- **Related IDs:** `BASELINE-001` (`TC-ARMY.32`), `RISK-007`.

---

### I-08: Player equipment tier is owned solely by `PlayerArmyManager` — VERIFIED
- **Rule:** Player equipment tier $\in \{1, 2, 3\}$. It upgrades sequentially, requires an active Barracks and the army garrisoned at the rally point, and is stored as a strict integer. Multipliers are queried dynamically via `EconomyConfig.get_army_equipment_multiplier()`. Units never store their own equipment tier.
- **Source Files & Functions:** `scripts/military/player_army_manager.gd` L221–393; `scripts/persistence/save_manager.gd` L867–873; `scripts/military/tactical_unit.gd` L102–111.
- **Related IDs:** `RISK-003`.

---

### I-09: NPC military units are independent of player equipment — VERIFIED
- **Rule:** Tactical unit equipment damage multipliers apply only when `faction_id == "player"`. `EnemyTacticalUnit._ready()` explicitly sets `owning_faction_id` (or `"enemy"`), ensuring enemy units always evaluate to fixed multiplier 1.0. Abstract NPC battle tiers are constants (`rival_military = 2`, others = 1).
- **Source Files & Functions:** `scripts/military/tactical_unit.gd` L102–111; `scripts/military/enemy_tactical_unit.gd` L31–35; `scripts/combat/battle_campaign_manager.gd` L265, L738.
- **Related IDs:** `RISK-003`.

---

### I-10: Tactical unit roster mirrors strategic army count — **PARTIAL**
- **Rule:** `TacticalMilitaryManager.units.size()` must equal `PlayerArmyManager.get_army_count()`, synchronized via `sync_with_player_army()`.
- **Architectural Divergence:** Stationarity and distance rules create split operational subsets:
  - `get_field_units()`: Requires distance $>5$ from rally **and** stationary (`movement_state != MOVING`). Used for siege launch eligibility and offensive campaign deployment.
  - `get_all_field_units()`: Ignores movement state. Used for ongoing siege combat evaluation.
  - Synchronization logic spans two large files ($>1200$ lines each) via `sync_state_from_tactical` and `sync_with_player_army`.
- **Source Files & Functions:** `scripts/military/tactical_military_manager.gd` L175–260; `scripts/military/player_army_manager.gd` L599–606, L994–1075.
- **Related IDs:** `GAP-004`.

---

### I-11: Field siege lifecycle and clean terminal resolution — VERIFIED
- **Rule:** Exactly one active siege per objective. Terminal paths (`VICTORY`, `DEFEAT`, `WITHDRAWAL`) route through `_resolve_siege_outcome()`, clearing the active flag and emitting `field_siege_resolved`. Victory transfers outpost ownership and credits plundered stock. Failed tactical attack orders after a successful launch do not roll back the siege record (retained as active for retry).
- **Source Files & Functions:** `scripts/combat/field_siege_manager.gd`; `scripts/world/world_view.gd` L1070–1117.
- **Related IDs:** `FIXED-001`, `GAP-001`, `RISK-002`.

---

### I-12: AI diplomacy actions must route through public signalling APIs — VERIFIED
- **Rule:** AI diplomacy changes (war/peace) must invoke `FactionManager.declare_war()` or `propose_treaty("peace")` so that global signals (`war_declared`, `peace_signed`) fire. These signals drive defensive garrison spawns, raid cancellations in `BattleCampaignManager`, and siege withdrawals in `FieldSiegeManager`.
- **Source Files & Functions:** `scripts/factions/faction_manager.gd` L855, L890; `scripts/combat/battle_campaign_manager.gd`; `scripts/world/world_view.gd`.
- **Related IDs:** `RISK-004`.

---

### I-13: Save schema backward-compatibility & fail-closed restoration — VERIFIED
- **Rule:** Save schema modifications must maintain backward-compatible migration. `SaveManager.validate_save_data()` must reject invalid types fail-closed before any world modifications occur. Deserialization must snapshot state (`pre_load_snapshot`) and execute recursive rollback if tactical/enemy/siege deserialization fails. Combat targets are resolved only after all entities exist.
- **Autosave Slot Isolation (BUG-003):** Autosaves write strictly to `user://saves/autosave.json` (`AUTOSAVE_PATH`), maintaining independent backup rotation without overwriting the player's manual save slot (`world_save.json`). Both slots feature independent crash-safe recovery (`.bak`, `.tmp`, `.bak.old`) and player-facing restore triggers in HUD and Main Menu. Verified across 10 scenarios in `scripts/test/test_save_slot_isolation.gd`.
- **Source Files & Functions:** `scripts/persistence/save_manager.gd`; `scripts/world/world_view.gd` L2541; `scripts/ui/hud.gd`; `scripts/ui/main_menu.gd`.
- **Related IDs:** `BUG-003` (CLOSED), `RISK-005`.

---

### I-14: Simulation calendar and time progression ordering — VERIFIED
- **Rule:** `TimeManager` accumulates real-time seconds into integer hours. On day rollover, `hour_passed` fires before `day_passed`. In `day_passed`, `ResourceManager` (autoload) executes first (food upkeep), followed by `WorldView` (events, AI factions, army upkeep, raids, autosave). Military tactical movement runs on frame delta, pausing when speed is 0.
- **Source Files & Functions:** `scripts/core/time_manager.gd`; `scripts/world/world_view.gd` L2366–2478.
- **Related IDs:** `BUG-003`.

---

### I-15: Player-facing UI feedback must truthfully reflect simulation outcomes — **VERIFIED**
- **Rule:** UI banners and feedback labels must show success only when the underlying simulation manager succeeded. Failures must display error banners with the failure reason.
- **Current State:**
  - *Package 2J Field Siege Attack Order:* **VERIFIED.** Displays a red error banner (`Lệnh Tấn Công Thất Bại`) when `issue_attack_order()` fails.
  - *Offensive Campaign Feedback:* **VERIFIED (RISK-008 RESOLVED).** `HUD.attack_faction()` inspects `report.victor` and branches cleanly into Victory (`Chiến Thắng!`, green), Defeat (`Thất Bại Chiến Dịch!`, red error), Stalemate (`Bất Phân Thắng Bại`), and Launch Failure (`Không Thể Tấn Công`), verified across 8 scenarios in `scripts/test/test_campaign_result_feedback.gd`.
- **Source Files & Functions:** `scripts/world/world_view.gd` L1097–1103; `scripts/ui/hud.gd` L1167–1205; `scripts/combat/battle_campaign_manager.gd` L805–809.
- **Related IDs:** `RISK-008` (CLOSED), `FIXED-001`, `GAP-001`.
