# KINGDOMS UNBOUND — Scope Decisions & Ambiguity Resolutions

## Document Status
- **Author:** Antigravity Autonomous Agent
- **Date:** 2026-10-12
- **Authority:** Secondary to `MASTER_PROMPT.md` and `docs/GDD.md`.
- **Purpose:** Formally documents all resolved design ambiguities, baseline configuration defaults, deferred systems, and architectural compromises.

---

## 1. Ambiguity Resolutions (Mandatory Master Prompt Items)

### 1.1 Starting Jobs vs. Starting Buildings
- **Problem:** `docs/GDD.md` allocates starting jobs to 2 Miners, 2 Researchers, and 2 Guards, but the starting settlement lacks a Mine, Research Hall, or Barracks.
- **Resolution:** Citizens cannot be assigned to workplaces that do not exist.
- **Starter Allocation (24 citizens total):**
  - **Farmers:** 5 (assigned to starter Farm)
  - **Woodcutters:** 4 (assigned to starter Woodcutter Camp)
  - **Builders:** 3 (assigned to construction tasks)
  - **Haulers:** 3 (assigned to logistics / transport)
  - **Idle / Unassigned:** 9 (available pool)
- **Unlock Rule:** Miner, Researcher, and Guard jobs unlock strictly when their corresponding workplace structures are constructed and active.

### 1.2 Initial Buildings & Starting Resources
- **Problem:** Starting inventory lists materials while starter buildings already exist on map generation.
- **Resolution:** The starter structures (Town Hall 3×3, 4 Houses 2×2, Farm 2×2, Storehouse 2×2, Woodcutter Camp 2×2) are generated as already constructed and operational during world initialization.
- **Starting Inventory:** The GDD starting amounts represent the net post-settlement stock placed in the Storehouse/Town Hall. Initial structures are never billed a second time against this inventory:
  - Food: 150
  - Wood: 120
  - Stone: 60
  - Ore: 0
  - Metal: 20
  - Tools: 15
  - Magic Crystal: 5
  - Herbs: 10
  - Treasury: 200 Gold
- All values reside in a central configuration resource (`StarterConfig.tres` / `EconomyConfig.gd`).

### 1.3 Food Balance, Seasons & Starvation Pacing
- **Problem:** 24 citizens consume 19.2 Food/day (0.8 Food/citizen/day). 5 Farmers produce 25 Food/day at base (5.0 Food/farmer/day). In Winter (modifier 0.5), output is 12.5 Food/day, yielding a daily deficit of -6.7 Food/day.
- **Resolution:**
  - **Calendar:** 4 seasons (Spring, Summer, Autumn, Winter), 10 game-days per season (40-day year).
  - **Starting Season:** Game begins on Year 1, Spring, Day 1 (modifier 1.0).
  - **Seasonal Farm Modifiers:**
    - Spring: 1.0 (25.0 Food/day)
    - Summer: 1.2 (30.0 Food/day)
    - Autumn: 1.0 (25.0 Food/day)
    - Winter: 0.5 (12.5 Food/day)
  - **Simulation Ticks:** Daily consumption and seasonal transitions occur at game-day midnight (00:00).
  - **Starvation Escalation:** Food hitting 0 NEVER causes instant death. Instead:
    - Stage 1 (Food = 0): "Nạn đói" (Starvation) status applied. Morale drops by -15/day, Fatigue +20/day.
    - Stage 2 (Continued starvation): Health drops by 5%/day. Citizens prioritize eating if any food arrives.
    - Stage 3 (Fatal threshold): Death occurs only when citizen Health reaches 0.
    - Recovery: When Food > 0, citizens consume food, starvation status is cleared, and health naturally recovers at 10%/day.

### 1.4 Population Growth & Prosperity Victory
- **Problem:** Prosperity victory requires $\ge 30$ population, but game starts with 24. GDD mentions probabilistic birth/immigration without clear deterministic gating.
- **Resolution:**
  - **Immigration Gating:** Every 3 game-days at 06:00, if:
    1. Housing Capacity > Current Population
    2. Available Food $\ge 30$
    3. Settlement Stability $\ge 50\%$
    4. Settlement Morale $\ge 60\%$
  - Then 1–2 immigrants arrive at the Town Hall.
  - Complex family genetics and birth cycles are deferred to post-MVP; immigration is the deterministic growth mechanism.
  - **Victory Hold:** All prosperity criteria must be maintained for 5 consecutive game-days (120 game-hours). If any metric drops below threshold, the 5-day timer resets to 0.

### 1.5 Collapse Conditions & Recovery Windows
- **Problem:** GDD defines collapse qualitatively ("loss of governmental capacity").
- **Resolution:** Deterministic failure states:
  1. **Extinction:** Population reaches 0 $\to$ Immediate collapse.
  2. **Town Hall Loss:** If Town Hall is destroyed, a 3-game-day emergency timer starts. If not rebuilt/repaired to $\ge 50\%$ health before expiry $\to$ Collapse.
  3. **Total Anarchy:** Stability reaches 0% for 3 continuous game-days $\to$ Collapse.
- **Explanatory UI:** Collapse warning banner displays exact cause, severity, and remaining countdown.

### 1.6 Storage, Buffers & Logistics
- **Problem:** Ambiguity between global magic inventory and physical item hauling.
- **Resolution:** Single Authoritative Resource Ledger (`ResourceManager`):
  - **Total Stock** = `Storehouse Stock` + `Town Hall Stock` + `Local Building Buffers`.
  - **Available Stock** = Total stock minus `Reserved Stock`.
  - Production outputs deposit first to the workplace's local output buffer.
  - Haulers physically travel to workplace, pick up cargo, navigate to Storehouse/Town Hall, and deposit items.
  - Only deposited goods become part of central available stock for construction/crafting.
  - Double-spending is prevented via atomic reservations (`reserve_resource(type, amount)`).

### 1.7 Job Lifecycle Semantics
- **Problem:** Contradictory states or workers getting stuck when jobs fail.
- **Resolution:** Strict job state machine:
  `Available` $\to$ `Reserved` $\to$ `In Progress` $\to$ `Completed` / `Failed` / `Cancelled`.
  - If target becomes unreachable or destroyed, worker releases reservation, drops carried items to nearest accessible tile or returns them, and transitions to `Idle`.

### 1.8 Trade & Faction Simulation
- **Problem:** Full physical trade caravans across large world borders would exceed initial milestone scope.
- **Resolution:**
  - Abstract faction state machine with deterministic periodic economy ticks.
  - Visiting merchant caravans arrive at Town Hall on scheduled days.
  - Transactions are atomic (all-or-nothing check on price, stock, and storage capacity).
  - Combat resolved via deterministic `BattleResolver` calculating casualties and morale from equipment, numbers, and defense ratings.

### 1.9 Legacy & Achievements Scope
- **Problem:** Cosmetic Legacy unlocks distract from core colony simulation stability.
- **Resolution:** Deferred to Phase 7/8. No core gameplay system depends on Legacy cosmetics.

### 1.10 Visual Projection & Localization
- **Problem:** Projection inconsistencies and language fragmentation.
- **Resolution:**
  - 2D dimetric isometric projection (2:1 slope, 32×16 px diamond ground tiles).
  - Ground contact anchors for all entities (`y_sort_enabled = true`).
  - Visible rooftops and SW/SE wall facades on all multi-tile buildings.
  - Player-facing UI in Vietnamese; internal IDs, logs, code, and comments in English.

### 1.11 Live War & Settlement Defense Battle Loop (Package 1K)
- **Problem:** Declaring war had no production consequence in the game loop; `BattleResolver` was abstract without live triggers.
- **Resolution:**
  - **Raid Scheduling:** War declaration triggers first raid after 3 game-days; recurring raids execute every 5 game-days while war persists and enemy military power > 0.
  - **Abstract Troops:** Mapped deterministically from faction military power: `abstract_troops = clampi(roundi(military_power / 30.0), 1, 20)`.
  - **Guard Gating:** Defending garrison requires living citizens with `role == "guard"` AND an active Barracks. Citizens resting or seeking food count as garrison.
  - **Zero-Troop Handling:** 0 vs 0 produces stalemate with 0 casualties; unopposed raids against undefended settlements produce 0 defender casualties and 20% resource plunder. Casualties never exceed initial force count.
  - **Idempotent Mutations:** Raids tracked by stable ID (`faction_day_seq`); repeat processing rejected; plunder respects available (unreserved) stock.

### 1.12 Player Army Recruitment & Upkeep (Package 1L)
- **Problem:** Settlement defense relied solely on converting civilian citizens into Guards. Large garrisons cannibalized the civilian labor force and distorted colony growth.
- **Resolution:**
  - **Separation of Reserves:** Recruited army units are an abstract military reserve tracked in `PlayerArmyManager`, distinct from civilian `CitizenController` Guards. They do not consume housing capacity, inflate population displays, or require physical pathfinding.
  - **Barracks Capacity:** Each active Barracks provides capacity for 5 soldiers. Under-construction or inactive Barracks contribute 0 capacity.
  - **Atomic Recruitment:** Recruited at 20 Gold, 2 Metal, and 5 Food per soldier using fail-closed atomic cost reservation and commit.
  - **Daily Food Upkeep:** 1 Food per soldier charged on daily simulation ticks. Starvation transitions army to unsupplied (morale 45.0) without deleting soldiers or partially draining food.
  - **Casualty Absorption Priority:** Settlement battles deduct casualties from recruited army first, sparing civilian guards until army reserves are exhausted. Abstract army casualties do not trigger citizen death events.

### 1.13 Player Army Marching & Garrison Deployment (Package 1M)
- **Problem:** In Package 1L, recruited armies were purely abstract numbers locked to the settlement without physical presence or strategic positioning. However, full RTS squad micromanagement (individual soldier pathing, attack-move stances, formations) would overcomplicate the vertical slice.
- **Resolution (Issue ISSUE-005 Foundation):**
  - **Single Authoritative Army:** The recruited army acts as a unified company stationed at `current_cell`. No individual soldier node spam.
  - **Lightweight ArmyMarker:** One single dimetric visual node `ArmyMarker` displays company position, troop count, and deployment stance (`🛡️` for garrison, `⚔️` for field).
  - **Discrete Grid Marching:** Army navigates via existing `GridNavigation` A* pathfinder on the 64×64 simulation grid at $0.5$s per tile.
  - **Dynamic Obstruction Rerouting:** Obstacles built mid-march trigger automatic dynamic rerouting; trapped routes safely halt without crashing.
  - **Garrison Deployment Rule:** Armies in the field or in transit cannot participate in settlement defense and do not take raid casualties. Only armies garrisoned at the home Town Hall plaza rally point contribute to settlement defense.
  - **Deferred Combat Extensions:** Field battles against wandering mobs, manual siege controls, and multi-army management remain deferred to later combat packages.

### 1.14 Player-Led Abstract Offensive Campaigns (Package 1N)
- **Problem:** Players could recruit and march armies into the field (Packages 1L & 1M) and settlements faced incoming enemy raids (Package 1K), but players lacked a mechanism to project offensive military force and attack hostile factions.
- **Resolution:**
  - **Launch Gating:** Offensive campaigns require: standing army count $\ge 1$; field deployment status (`movement_state == MovementState.IDLE_AT_FIELD` and `current_cell != rally_cell`); target faction exists, is at war (`is_at_war == true`), and has remaining military power (`military_power > 0.0`).
  - **Atomic Fail-Closed Protection:** Ineligible targets or invalid deployment states reject attack orders atomically with clear Vietnamese HUD feedback, causing zero state mutations.
  - **Deterministic Battle Resolution:** Resolves via `BattleResolver.resolve_battle()` using a deterministic seed derived from `(world_seed * 37 + cur_day * 103 + hash(target_faction_id) + sequence * 19) & 0x7FFFFFFF`. Force dictionaries are duplicated before resolution to preserve caller immutability.
  - **Outcome Application:** Player casualties deduct from standing army via `PlayerArmyManager.remove_casualties()`. Target faction military power reduces by $30.0 \times \text{casualties}$, clamped to floor $0.0$.
  - **Post-Battle Army Normalization:** If all soldiers perish, the army automatically recovers to clean `GARRISONED` status at the home rally cell. Surviving soldiers remain deployed at their current field coordinate without teleporting.
  - **Event Reporting:** In-Game HUD displays informative Vietnamese event banners detailing casualties, combat scores, remaining troops, and enemy power.
### 1.15 Post-Battle Diplomatic Consequences (Package 1O)
- **Problem:** Resolving player-led offensive campaigns (Package 1N) and incoming settlement raids (Package 1K) inflicted physical casualties and altered faction military power, but diplomatic relations remained static after war initiation. This detached military actions from diplomatic standing and post-war realignment.
- **Resolution (GDD §10.2 & §10.4 Alignment):**
  - **Authoritative Named Penalties (Single Source of Truth):**
    - Canonically defined in `FactionManager`: `FactionManager.OPINION_PENALTY_OFFENSIVE_CAMPAIGN = 8.0` and `FactionManager.OPINION_PENALTY_SETTLEMENT_RAID = 10.0`.
    - Directly referenced by `BattleCampaignManager` to ensure zero duplicated definitions.
    - Player-led offensive campaign: Reduces target faction opinion by **8.0 points**.
    - Enemy settlement raid: Reduces attacking faction opinion by **10.0 points**.
  - **Strict Boundary Clamping:** All opinion adjustments clamp within the canonical `[-100.0, 100.0]` range via `FactionData.change_opinion()` and `FactionManager.modify_opinion()`. Both upper (+100.0) and lower (-100.0) boundary clamping are fully tested and enforced.
  - **War-Time Disposition Semantics:** While `is_at_war == true`, faction disposition remains strictly locked to `Disposition.HOSTILE` regardless of opinion shifts. Post-war disposition recalculates dynamically from opinion upon signing peace via `FactionData.sign_peace()`'s `change_opinion(20.0)` flow and explicit public helper `FactionData.recalculate_disposition()`.
  - **Single Signal Emission:** Successful battle consequences emit `FactionManager.relation_changed` exactly once per battle consequence.
  - **Fail-Closed Immutability:** Ineligible offensive attacks (0 troops, garrisoned, marching, not at war, 0 military power) and invalid/not-due/already-processed raids apply 0 opinion penalty and emit 0 signals.
  - **Persistence & Idempotency:** Opinion and disposition persist through existing `SaveManager` world state serialization/deserialization. Restoring world saves emits zero `relation_changed` signals and repeated loads execute idempotently without reapplying penalties.

### 1.16 Emerging Faction Ascension Gates (Package 1P)
- **Problem:** In existing code, `neutral_tribe` evolved when day $\ge 10$ and population $\ge 45$. However, GDD §10.3 describes ascension qualitatively based on population, essential resources, internal stability, and development time without numerical specifications, leaving resource and stability requirements unverified.
- **Resolution (GDD §10.3 Scope Decisions for MVP):**
  - **Deterministic Ascension Gate Thresholds:**
    - Time Gate: `ASCENSION_MIN_DAY = 10` (simulation day $\ge 10$).
    - Population Gate: `ASCENSION_MIN_POPULATION = 45` (tribe population $\ge 45$).
    - Resource Gates: `ASCENSION_MIN_WOOD = 60` (wood stock $\ge 60$) and `ASCENSION_MIN_HERBS = 30` (herbs stock $\ge 30$).
    - Stability Gate: `ASCENSION_MIN_STABILITY = 50.0` (stability $\ge 50.0$).
    - *Scope Clarification:* These values are deterministic engineering scope decisions for MVP testability; GDD §10.3 does not dictate specific numbers.
  - **Resource Consumption Policy:** Resource thresholds are validated as prerequisites, but **no resources are deducted** from the tribe upon ascension (no wood or herbs consumed).
  - **Single Emerging Power Rule:** The game world permits at most one emerging power. If any faction in the world already has `type == "emerging_power"`, ascension fails closed and cannot trigger.
  - **Ascension Outcome & Idempotency:**
    - Upon meeting all gates, the neutral tribe mutates: `type = "emerging_power"`, `name = "Liên Minh Rừng Thiêng"`, `military_power = 55.0`, `stability = 85.0`.
    - Emits `FactionManager.emerging_faction_ascended(tribe.id, tribe.name)` exactly once.
    - Subsequent simulation ticks check `type == "neutral_tribe"`, which evaluates to false, preventing duplicate state mutations or re-emission of signals.
  - **Persistence Compatibility:**
    - `SaveManager` serialization now records `resources` for all factions.
    - `SaveManager.apply_loaded_state_to_world()` restores `name`, `type`, and `resources` when present, preserving post-ascension identity and resources across save/load cycles with full backward compatibility.
  - **HUD Integration:**
    - Connected to `emerging_faction_ascended` in `HUD.set_faction_manager()` to display an event banner in Vietnamese (`"Thế Lực Mới Nổi! Liên Minh Rừng Thiêng đã chính thức trỗi dậy thành một cường bang mới!"`) and dynamically refresh the diplomacy menu.

- **1.17 Package 1Q — Faction Strategic Profiles & Existence Status (GDD §10.1 & §10.5):**
  - **Strategic Goal MVP Mapping:**
    - `rival_military`: `military_expansion` ("Mở rộng quân sự").
    - `rival_merchant`: `trade_dominance` ("Phát triển thương mại").
    - `neutral_tribe` (pre-ascension): `community_growth` ("Phát triển cộng đồng").
    - `neutral_tribe` (post-ascension / `emerging_power`): `consolidate_power` ("Củng cố thế lực").
    - *Scope Clarification:* Strategic Goal represents the faction's authoritative narrative/strategic agenda data model in MVP. Autonomous AI goal execution is deferred.
  - **Existence Status Scope & Fallback:**
    - `active` ("Hoạt động"): Faction is currently active in the game world. All initial factions start in this status.
    - `in_exile` ("Lưu vong"): Faction government in exile, establishing data model compatibility for capital loss recovery described in GDD §10.5.
    - `eliminated` ("Bị loại bỏ"): Faction eliminated from play.
    - *Boundary & Safety Rule:* Package 1Q implements the data model, serialization, UI rendering, and validation only. It does not introduce autonomous faction elimination rules, capital capture, or war/peace changes. Factions are not marked eliminated merely because military power reaches 0.
  - **Fail-Closed Validation Policy:**
    - `SaveManager.validate_save_data()` strictly validates `strategic_goal` against `FactionData.VALID_STRATEGIC_GOALS` and `existence_status` against `FactionData.VALID_EXISTENCE_STATUSES`. Invalid entries fail schema validation and abort load without mutating the live world.
    - Mutator setters `set_strategic_goal()` and `set_existence_status()` reject invalid strings and return false, leaving existing state untouched.
  - **Backward Compatibility:**
    - Legacy saves omitting these fields deserialize cleanly: `emerging_power` defaults to `consolidate_power`, `rival_military` to `military_expansion`, `rival_merchant` to `trade_dominance`, `neutral_tribe` to `community_growth`, and all default to `active` existence status.
  - **Diplomacy UI Contract:**
    - HUD faction cards render Vietnamese labels via centralized static helpers (`FactionData.get_strategic_goal_label()` and `FactionData.get_existence_status_label()`). Raw internal identifiers are never exposed directly to players.

- **1.18 Package 1R — Deterministic Faction Strategic Decision Engine (GDD §10.1 & §10.2):**
  - **Strategic Intent Layer Architecture:**
    - Dedicated evaluator class `FactionStrategyPlanner` (`scripts/factions/faction_strategy_planner.gd`) translates `FactionData` profile state into deterministic, explainable strategic intent outputs.
    - Decoupled from execution: Intent generation produces planning decisions, not direct gameplay mutations. No automatic war declarations, treaty changes, attacks, or resource mutations occur during evaluation.
  - **Deterministic Goal-to-Intent Canonical Mapping:**
    - `military_expansion` -> `military_buildup` ("Tăng cường quân sự").
    - `trade_dominance` -> `trade_expansion` ("Mở rộng giao thương").
    - `community_growth` -> `community_development` ("Phát triển cộng đồng").
    - `consolidate_power` -> `power_consolidation` ("Củng cố quyền lực").
  - **Structured Decision Output Contract:**
    - Evaluator returns a typed dictionary containing:
      - `faction_id: String` (ID of the evaluated faction).
      - `strategic_goal: String` (active canonical goal).
      - `intent_id: String` (mapped canonical intent, or `none` if ineligible/invalid).
      - `eligible: bool` (true only for active, valid factions).
      - `reason_code: String` (`GOAL_ALIGNED`, `WARTIME_POSTURE`, `INELIGIBLE_IN_EXILE`, `INELIGIBLE_ELIMINATED`, `ERR_INVALID_STATUS`, `ERR_INVALID_GOAL`, `ERR_NULL_FACTION`).
      - `posture: String` (`peacetime`, `wartime`, `exiled`, `eliminated`, `unknown`).
  - **Existence-Status Gating:**
    - Only `active` factions receive eligible active-world strategic intents (`eligible == true`).
    - Factions with `in_exile` or `eliminated` status return `eligible == false` with `intent_id == "none"`.
    - Zero military power alone does NOT eliminate a faction; status must be explicitly marked.
    - Status values are never automatically altered by the evaluator.
    - Only `active` neutral tribes can ascend to `emerging_power` (`can_emerging_faction_ascend() == true`). Inactive tribes (`in_exile`, `eliminated`) are strictly barred from ascension.
    - Daily neutral tribe population growth in `update_daily_simulation()` is strictly restricted to `active` tribes (`existence_status == STATUS_ACTIVE`). Inactive tribes (`in_exile`, `eliminated`) do not gain daily settlement population, reflecting that displaced governments in exile or eliminated factions do not host an active growing settlement on the world map.
  - **Daily Simulation Pipeline Integration:**
    - Evaluated in `FactionManager.update_daily_simulation(day)` after the neutral tribe ascension check, ensuring that post-ascension goals (`consolidate_power`) are immediately respected.
    - Factions are processed in stable alphabetical order (`sorted_ids.sort()`) exactly once per daily simulation tick.
    - Emits `FactionManager.strategic_intent_evaluated(faction_id, intent_data)` for each eligible active faction. Inactive factions (`in_exile`, `eliminated`) are suppressed from standard intent emission.
    - Query APIs `get_faction_strategic_intent(faction_id)` and `evaluate_all_strategic_intents()` provide deterministic read access on demand without requiring simulation ticks.
  - **Fail-Closed & State Invariance:**
    - Unrecognized goals, statuses, or null faction references return ineligible results with explicit error reason codes without throwing exceptions or mutating faction state.
    - Evaluation is strictly side-effect free: `id`, `name`, `type`, `disposition`, `opinion`, `military_power`, `stability`, `resources`, `population`, `is_at_war`, `has_nap`, `has_alliance`, `strategic_goal`, and `existence_status` remain 100% invariant across evaluations.
- **1.19 Deterministic Faction Strategic Intent Execution (GDD §10.1, §10.3, §10.5 — Package 1S):**
  - **Strict Planner vs. Executor Separation:** `FactionStrategyPlanner` remains a 100% pure, read-only decision evaluator. A dedicated execution layer `FactionStrategyExecutor` (`scripts/factions/faction_strategy_executor.gd`) executes bounded, deterministic, atomic faction actions once per simulation day per active faction.
  - **Canonical Action Contracts & Bounds:**
    - `military_buildup` (`military_expansion`): Consumes `10 Metal + 25 Gold` atomically from `FactionData.resources` and increases `military_power` by `+5.0` up to a ceiling of `120.0`. Allowed in both peacetime and wartime.
    - `trade_expansion` (`trade_dominance`): Allowed in peacetime only (`is_at_war == false`; fails closed with `BLOCKED_BY_WAR` when at war). Consumes `5 Tools`, adds `+30 Gold` (up to `1000 Gold` ceiling), and increases `stability` by `+2.0` (up to `95.0` ceiling).
    - `community_development` (`community_growth`): For pre-ascension `neutral_tribe` in `FactionManager.update_daily_simulation(day)`, honors the existing `+1` daily settlement population growth without consuming the non-consumptive ascension prerequisite reserves (`Wood >= 60`, `Herbs >= 30`). For general `community_growth` execution, consumes `10 Wood + 5 Herbs`, increases `population` by `+1` (up to `80` ceiling), and increases `stability` by `+2.0` (up to `90.0` ceiling).
    - `power_consolidation` (`consolidate_power`): Requires post-ascension `emerging_power` status (`type == "emerging_power"` and `strategic_goal == "consolidate_power"`). Does not execute a second mutation on the exact day ascension occurred (`ASCENDED_THIS_TICK`), preventing double-applied ascension boosts. On subsequent days, consumes `15 Wood + 10 Herbs`, increases `military_power` by `+4.0` (up to `90.0` ceiling), and increases `stability` by `+2.0` (up to `95.0` ceiling).
  - **Daily Idempotency, Faction Resource Contract & Persistence:**
    - `FactionStrategyExecutor` records `last_executed_days[faction_id] = day` upon execution, rejecting repeat same-day or earlier-day calls with `ALREADY_EXECUTED_TODAY`.
    - `FactionManager` also guards `neutral_tribe` pre-ascension daily population growth via `_last_tribe_growth_day` so same-day re-invocations or post-load replays cannot double-increment population.
    - **Authoritative Faction Resource Contract (`BUG-1S-02`):** Each faction's `resources` field must be a `Dictionary` mapping canonical resource keys (`EconomyConfig.ALL_RESOURCES`) to finite non-negative integer quantities (`int >= 0` or integral `float` after JSON parsing). `SaveManager.validate_save_data()` rejects non-Dictionary `resources`, unknown keys, negative quantities, strings, booleans, fractional floats, or non-finite values fail-closed before any world mutation. `FactionStrategyExecutor` also validates `fac.resources` fail-closed (`ERR_INVALID_RESOURCES`) prior to any cap or cost evaluation, ensuring invalid `Gold` or other resource entries never bypass checks or cause partial state mutations.
    - **Clock-Synchronized Strategy Persistence (`BUG-1S-01`):** `SaveManager` persists and validates `factions.strategy_executor` (`last_executed_days` and `last_tribe_growth_day`). In addition to absolute bounds (`1..36500`, or `-1` for `last_tribe_growth_day`), `SaveManager.validate_save_data()` enforces `last_executed_day <= game_clock.current_day` and `last_tribe_growth_day <= game_clock.current_day` whenever `game_clock.current_day` is present, rejecting future execution timestamps before `apply_loaded_state_to_world()` mutates the world. As a second layer of defense, `FactionStrategyExecutor.deserialize(data, current_day)` and `FactionManager.deserialize_executor_state(data, current_day)` refuse to restore any execution or growth day greater than `current_day` (when `current_day >= 1`), while resetting cleanly to `-1` for legacy saves omitting `strategy_executor`.
- **1.20 Deterministic Autonomous Faction Diplomacy (GDD §10.1, §10.2, §10.5 — Package 1T):**
  - **Pure Diplomacy Planner (`FactionDiplomacyPlanner`):** Implemented in `scripts/factions/faction_diplomacy_planner.gd` as a stateless, side-effect-free evaluator (`evaluate_diplomatic_action(fac: FactionData) -> Dictionary`) returning `faction_id`, `action_id` (`declare_war`, `sign_peace`, `none`), `eligible`, `reason_code`, `inputs`, and Vietnamese `explanation`.
  - **Authoritative War Initiation Thresholds (`declare_war`):** Requires `existence_status == "active"`, `is_at_war == false`, `has_nap == false`, `has_alliance == false`, `opinion <= -60.0` (`WAR_MAX_OPINION`), `military_power >= 65.0` (`WAR_MIN_MILITARY_POWER`), `stability >= 50.0` (`WAR_MIN_STABILITY`), and either `strategic_goal == "military_expansion"` or (`type == "emerging_power"` and `strategic_goal == "consolidate_power"`). Pre-ascension `neutral_tribe`, unascended `consolidate_power`, and `trade_dominance` factions cannot autonomously declare war.
  - **Authoritative Peace Thresholds (`sign_peace`):** Requires `is_at_war == true`, `existence_status` in `["active", "in_exile"]` (`eliminated` factions never execute diplomacy), and either `military_power <= 20.0` (`PEACE_MAX_MILITARY_POWER`) or `stability <= 25.0` (`PEACE_MAX_STABILITY`).
  - **Execution Routing, Ordering & Anti-Oscillation (`FactionManager`):** `FactionManager.execute_faction_diplomatic_action(faction_id, day, decision_override)` validates planner agreement fail-closed, enforces at-most-once daily evaluation per faction via `_last_diplomacy_days`, and routes transitions through existing `declare_war(faction_id)` and `propose_treaty(faction_id, "peace")` APIs so `war_declared`, `peace_signed`, `relation_changed`, `BattleCampaignManager` raid scheduling/cancellation, and `HUD` Vietnamese event banners work uniformly. In `FactionManager.update_daily_simulation(day)`, autonomous diplomacy runs in sorted faction-ID order **before** daily strategic intent evaluation/execution.
  - **Save/Load Validation (`SaveManager`):** `_last_diplomacy_days` is persisted under `factions.strategy_executor.last_diplomacy_days` (`SAVE_SCHEMA_VERSION = 1`), validated fail-closed against `[1, 36500]` and `<= game_clock.current_day`, and filtered by `FactionManager.deserialize_executor_state(data, current_day)` with full legacy save compatibility.
- **1.21 Pairwise Faction Relations Foundation (GDD §10.1, §10.2, §10.5 — Package 1U):**
  - **Canonical Pairwise Relationship Model (`FactionRelationData`):** Implemented in `scripts/factions/faction_relation_data.gd` as the single authoritative relationship record for each unordered pair of distinct NPC factions `(faction_a < faction_b)`, keyed by `pair_key = faction_a + "__" + faction_b`. Supports directional opinions (`opinion_a_to_b`, `opinion_b_to_a`, initialized to `0.0`, clamped to `[-100.0, 100.0]`) and shared war/treaty state (`is_at_war`, `has_nap`, `has_alliance`).
  - **Strict Separation from Player Diplomacy:** Pairwise NPC-to-NPC relationships are stored in `FactionManager._pairwise_relations` and emit pair-specific signals (`faction_pair_opinion_changed`, `faction_pair_war_declared`, `faction_pair_peace_signed`, `faction_pair_treaty_signed`). They never repurpose `FactionData` player-facing fields or trigger `BattleCampaignManager` settlement raids.
  - **Validated Transitions & Existence Status Guards:** War declaration (`declare_war_between_factions`, `-50.0` opinion delta, clears NAP/Alliance), NAP (`sign_nap_between_factions`, mutual opinion `>= 0.0`, `+15.0` delta), and Alliance (`sign_alliance_between_factions`, mutual opinion `>= 60.0`, `+25.0` delta, sets `has_nap = true`) require both factions to be `active`. Peace (`sign_peace_between_factions`, `+20.0` delta) permits `active` or `in_exile` factions while blocking `eliminated` factions.
  - **Persistence & Fail-Closed Validation (`SaveManager`):** Persisted under `factions.pairwise_relations` (`SAVE_SCHEMA_VERSION = 1`), validated fail-closed in `SaveManager.validate_save_data()` against self-relations, unknown IDs, non-canonical ordering, mismatched keys, out-of-range/non-finite opinions, non-boolean flags, and contradictory war/treaty flags, with clean neutral fallback for legacy saves.
- **1.22 Functional Automation Graph MVP (GDD §7.3, Stage 11 HTML Reference — Package 1V):**
  - **Data Model & Schema:** `AutomationProgram` (`scripts/economy/automation_program.gd`) encapsulates graph programs with `id`, `name`, `enabled`, `priority`, `nodes`, and `edges`, with full serialization and deserialization.
  - **Strict Fail-Closed Validation (`AutomationGraphValidator`):** Validates node schemas, coordinates, type/subtype constraints, trigger presence, duplicate IDs, port compatibility (Flow ports `out`, `true`, `false` vs Boolean ports `bool`, `cond`, `inA`, `inB`), BFS reachability + backward data dependency tracing, IfElse branch completeness, and iterative DFS cycle detection.
  - **Graph Execution Engine (`AutomationManager`):** Evaluates condition nodes (`ResourceCompare`, `CitizenFatigue`, `StorageFull`), combinational logic gates (`AND`, `OR`, `NOT`), dynamic `IfElse` branching, and authoritative action execution (`AssignRole`, `BoostJobPriority`, `EmitLog`) with per-citizen action locking. Enforces strict step budget (`MAX_STEPS_PER_RUN = 60`) and respects simulation pause (`is_paused: true`).
  - **Dry Run Simulation Guarantee:** Test/Simulate mode executes 100% side-effect-free, guaranteeing zero mutation to citizen roles, resource stocks, job priorities, or persistent execution logs, while returning a complete diagnostic execution trace.
  - **Visual Editor UI (`AutomationEditor`):** Implemented in `scenes/ui/automation_editor.tscn` and `scripts/ui/automation_editor.gd`, embedded in `HUD` (`hud.tscn`, shortcut `G`, BottomBar button `AutomationBtn`). Features `GraphEdit`/`GraphNode` canvas, interactive wiring, parameter inspector, validation status badge, and dry-run simulation log viewer.
  - **Persistence & Compatibility:** Persisted in `SaveManager` under `data["automation"]` (`SAVE_SCHEMA_VERSION = 1`), with fail-closed validation on malformed graphs and seamless legacy save compatibility without schema bump.
  - **Preset Rules Non-Regression:** Existing preset rules in `AutomationManager` (`food_emergency_threshold`, `buffer_congestion_ratio`, `winter_prep_food_threshold`) remain fully operational alongside visual graph programs.
- **1.23 Tactical Military Units & Command MVP (GDD §11.1, §11.2, Stage 11 HTML Reference — Package 1W & Final Hardening & Post-Hardening Review & Final Review & Garrison Transition Audit):**
  - **Single Authoritative Source of Truth:** `PlayerArmyManager` remains the authoritative source of truth for soldier capacity, recruitment costs/transactions, daily food upkeep, combat morale, and settlement campaign casualties. `TacticalMilitaryManager` strictly maintains 1:1 synchronization ($|\text{tactical\_units}| == \text{soldier\_count}$). Abstract army casualties do not trigger civilian death events.
  - **Occupancy-Safe Spawn & Destination Allocation:** Multiple sequential recruitments strictly disallow coordinate overlap with existing tactical units. The spawn allocator searches outward from `rally_cell` excluding cells occupied or reserved by active units. Formation slot computation (`compute_formation_slots`) enforces pairwise distinct destinations and excludes cells occupied by unselected units; if insufficient non-overlapping walkable slots exist, the entire order is rejected atomically with zero partial movement.
  - **Strict Garrison-State Invariant & Transition Audit (Blocker Resolution):**
    - `PlayerArmyManager` strictly enforces the invariant that a non-empty army can **never** enter `MovementState.GARRISONED` while any tactical soldier is moving (`order_state == MOVING`) or outside `RALLY_PERIMETER_DISTANCE = 5`.
    - `get_settled_state_for_cell(cell: Vector2i) -> int`: Shared authoritative predicate enforcing consistent state resolution across `cancel_move()`, runtime route obstruction failure in `advance_movement()`, and invalid route recovery in `deserialize()`. If `cell == rally_cell`, returns `GARRISONED` only if `soldier_count == 0` or all tactical units are idle within perimeter; returns `MARCHING` if tactical units are in transit; returns `IDLE_AT_FIELD` if units are idle outside perimeter.
    - `cancel_move()`: Halts strategic route without prematurely forcing `GARRISONED` at `rally_cell`. Tactical units in transit continue moving while the strategic layer maintains `MARCHING` until real settlement. If tactical units are halted outside perimeter, state cleanly transitions to `IDLE_AT_FIELD`.
    - `sync_state_from_tactical()`: Strictly prevents `GARRISONED` from persisting if any tactical unit is in `OrderState.MOVING`, automatically transitioning `movement_state` to `MARCHING`.
    - Integrated Save/Load Ordering: Following `TacticalMilitaryManager.deserialize()`, `SaveManager` guarantees `PlayerArmyManager.sync_state_from_tactical()` execution, preventing stale pre-load strategic garrison status from persisting over moving or field units.
  - **Strict Deserialization Garrison Gating & Empty Tactical Roster Fail-Closed (Final Invariant Audit):**
    - *Save/Load Sequencing & Intermediate GARRISONED Elimination:* Because `PlayerArmyManager.deserialize()` runs in Step 13 before `TacticalMilitaryManager.deserialize()` in Step 17, `PlayerArmyManager.deserialize()` avoids publishing an intermediate or unjustified `GARRISONED` state when `soldier_count > 0`. If `tactical_military_mgr` is present with matching units (`get_unit_count() == soldier_count`), state reconciles immediately via `get_settled_state_for_cell(current_cell)`; if units are not yet loaded (`get_unit_count() != soldier_count`), `deserialize()` sets tentative `IDLE_AT_FIELD` without publishing `GARRISONED`.
    - *Deserialization Signal Isolation (`is_deserializing`):* `PlayerArmyManager` flags `is_deserializing = true` during `deserialize()`, preventing `TacticalMilitaryManager._on_army_changed` from prematurely auto-spawning dummy garrison units during save restoration before Step 17 loads the authentic tactical roster.
    - *Empty Roster Fail-Closed Invariant:* An empty tactical roster (`all_units.is_empty()`) when `soldier_count > 0` strictly returns `false` in `are_all_tactical_units_settled_at_base()`. If `sync_state_from_tactical()` runs when `soldier_count > 0` and `all_units.is_empty()`, any existing `GARRISONED` state is immediately cleared and transitioned to `IDLE_AT_FIELD`.
    - *Save Validator Fail-Closed Enforcement:* `SaveManager.validate_save_data()` strictly fails closed if `player_army.soldier_count > 0` and `tactical_military.units` is empty or has mismatched size (`units_val.size() != expected_soldiers`).
    - *Genuine Zero-Soldier Army Normalization:* Armies with `soldier_count == 0` legitimately normalize to `GARRISONED` at `rally_cell` in both unit `deserialize()` and integrated `apply_loaded_state_to_world()`. Legacy saves omitting `tactical_military` remain fully supported via `deserialize_legacy()`.
  - **Dedicated Return-Home Garrison Allocation, Strict GARRISONED Gating & Command Idempotency (Post-Hardening & Final Review):**
    - Returning to base (`order_return_home()` / `order_return_all_to_rally()`) uses a dedicated, deterministic slot allocator (`compute_garrison_return_slots()`) rather than the wide lateral formation allocator, guaranteeing all assigned slots are strictly within `RALLY_PERIMETER_DISTANCE = 5` Manhattan distance of `rally_cell`.
    - Fail-closed atomic guarantee: if fewer than `count` distinct, walkable, unoccupied cells exist within perimeter, or if any unit lacks a walkable route to its assigned slot, the return command is rejected atomically (`{"success": false}`) without partial movement, state alteration, or unintentional selection mutation (`select_all`).
    - Route failure propagation: failed return commands propagate their failure to `PlayerArmyManager.order_return_home()` without clearing `current_path` or altering strategic state.
    - Strict GARRISONED Gating: the strategic army does NOT prematurely transition to `GARRISONED` merely because the strategic center reached `rally_cell` or because `order_return_home()` was called. While tactical units are still in transit, `movement_state` remains `MARCHING`. Only when all tactical units are verified idle and within perimeter does `sync_state_from_tactical()` finalize the state to `GARRISONED`.
    - Command Idempotency & Progress Preservation: reissuing an identical return-home command while units are in transit does not reset `step_accumulator`, does not re-issue destructive route replacements, does not cause units to stall, and strictly preserves the in-transit `MARCHING` state.
    - Stability: subsequent `tactical_state_updated` signals maintain `GARRISONED` without reverting to `IDLE_AT_FIELD`.
  - **Consistent Definition of Ready Field Troops & Offensive Gate (Post-Hardening Fix B):**
    - Formal taxonomy:
      1. *Physically outside unit:* Any unit with `grid_distance(cell, rally_cell) > 5`.
      2. *Moving unit:* Any unit with `order_state == OrderState.MOVING`.
      3. *Ready / eligible field troop:* A unit with `grid_distance(cell, rally_cell) > 5 AND order_state != OrderState.MOVING`.
    - Both `BattleCampaignManager.can_launch_offensive_campaign()` and `launch_offensive_campaign()` query ready field troops via `PlayerArmyManager.get_field_unit_count()`.
    - Moving units are never counted as assembled offensive participants; campaigns cannot launch if ready field troop count is 0.
    - Attacking force size `atk_troops` strictly equals the ready stationary field force, never total soldier count or moving units.
  - **Defensive & Offensive Casualty Predicate Consistency (Post-Hardening Fix C):**
    - Moving units (`order_state == MOVING`) are strictly ineligible to be taken as casualties in either settlement defense or field campaigns (`if u.order_state == MOVING: return false`).
    - Defensive raid casualties strictly target stationary garrison-eligible units (`dist <= 5 and order_state != MOVING`); field campaign casualties strictly target stationary field-eligible units (`dist > 5 and order_state != MOVING`).
    - Clamping: `PlayerArmyManager.remove_casualties()` clamps casualties to the eligible stationary pool (`get_defending_soldier_count()` or `get_field_unit_count()`), strictly preserving `soldier_count == tactical_roster.size()`.
    - Unconditional `army_changed.emit(soldier_count, capacity)` ensures immediate UI synchronization.
  - **Fail-Closed Tactical Persistence & Validation-Before-Mutation (Fix B):**
    - Legacy reconstruction is strictly restricted to legacy saves that **completely omit** the `tactical_military` key. If `tactical_military` is present, it must be a valid Dictionary with an `Array` of `units` whose size matches `soldier_count` exactly, even if `player_army` lacks `movement_state` (removing the `is_legacy_army` bypass).
    - Moving units (`order_state == "moving"`) must specify a valid `target_cell` and a non-empty `current_path` whose final waypoint strictly equals `target_cell`. Idle/holding units must have an empty `current_path`.
    - Both `TacticalMilitaryManager.deserialize()` and `TacticalUnit.deserialize()` enforce validation-before-mutation: all records, coordinates, and paths are validated fail-closed prior to invoking `clear_all_units()` or mutating live runtime structures.
    - If deserialization fails, `apply_loaded_state_to_world()` returns `{"success": false}` fail-closed instead of falling back to legacy reconstruction or continuing in a corrupted state.
  - **Field-Only Campaigns & Strict Location-Restricted Casualties (Fix A & Fix D):**
    - *Offensive Campaign Gate:* Launching an offensive campaign strictly requires field troops (`get_field_unit_count() > 0`) assembled outside `RALLY_PERIMETER_DISTANCE = 5` and idle (`IDLE_AT_FIELD`). Attacking force size `atk_troops` equals `get_field_unit_count()`, never total soldier count.
    - *Clamped Attacker Casualties:* Attacker casualties are clamped to `atk_troops` (`clampi(report.attacker_casualties, 0, atk_troops)`).
    - *Strict Location-Restricted Casualty Allocation:* Casualty removal is strictly location-restricted (`location_restricted = true`). Offensive campaign casualties (`from_field = true`) never consume garrisoned units; defensive settlement raid casualties (`from_field = false`) never consume units deployed to the field.
    - *Consistent UI Signal Emission (Fix D):* `PlayerArmyManager.remove_casualties()` unconditionally emits `army_changed.emit(soldier_count, get_army_capacity())` after casualty application, ensuring HUD elements and `ArmyMarker` update immediately without requiring subsequent recruitment or reload.
  - **Deterministic Strategic vs. Tactical Movement Contract (Fix C):**
    - *1. Full strategic march with synchronized tactical units:* Issuing `order_move(dest)` dispatches all tactical units in formation toward `dest` while setting the strategic army path. `PlayerArmyManager.advance_movement(delta, speed_mult)` delegates stepping to `TacticalMilitaryManager.advance_movement()`, ensuring identical physical cell-by-cell progression in both runtime and headless test environments.
    - *2. Subset tactical movement during an active march:* If a subset of units is given an independent tactical order while the strategic army is on a march, those units execute their order while remaining units continue. `sync_state_from_tactical()` never clears `current_path` or aborts the strategic march while `movement_state == MARCHING and not current_path.is_empty()`.
    - *3. Return-home order issued mid-march:* Issuing `order_return_home()` redirects the strategic route toward `rally_cell` and issues `order_return_all_to_rally()`, smoothly reversing unit trajectories.
    - *4. Arrival timing & No Forced Snapping:* Units advance tile-by-tile via `advance_movement()`. Forced teleportation snapping (`arrive_all_at_destination()`) is removed. The strategic march completes cleanly when the strategic destination or rally point is reached.
  - **Consolidated Final Audit & Invariant Closure (Consolidated Audit Gate):**
    - *Truthful Garrison Invariant (Invariant A):* An army with `soldier_count > 0` may be `GARRISONED` if and only if: (1) `tactical_military_mgr != null`, (2) `tactical_military_mgr.get_unit_count() == soldier_count`, (3) no tactical units are moving, and (4) all tactical units reside within `RALLY_PERIMETER_DISTANCE = 5` of `rally_cell`.
    - *Missing Manager Fail-Safe:* If `tactical_military_mgr == null` while `soldier_count > 0`, the army strictly defaults to safe `MovementState.IDLE_AT_FIELD` across all queries (`get_settled_state_for_cell`), state syncs (`sync_state_from_tactical`), arrivals (`_arrive_at_destination`), and save loads (`deserialize`). It never reports `GARRISONED` without an authoritative tactical roster.
    - *Empty or Mismatched Tactical Roster Fail-Closed:* Any positive soldier count with 0 or mismatched tactical units strictly refuses `GARRISONED` (defaults to `IDLE_AT_FIELD`) and fails closed on save validation (`SaveManager.validate_save_data()`).
    - *Genuine Zero-Soldier Army Normalization:* An army with `soldier_count == 0` legitimately normalizes to `GARRISONED` at `rally_cell`, with `current_cell` and `destination_cell` matching `rally_cell`, even when `tactical_military_mgr == null`.
    - *Manager Bi-directional Pairing:* `TacticalMilitaryManager._init()` and `set_player_army_manager()` establish bi-directional pairing with `PlayerArmyManager` (`player_army_mgr.set_tactical_military_manager(self)`), preventing asymmetric signal attachment or orphaned state synchronization.
    - *Settlement Convergence in Return-Home:* In `order_return_home()`, if tactical units are not moving but outside perimeter (or if manager is missing/mismatched), the strategic state transitions via `get_settled_state_for_cell(current_cell)` to `IDLE_AT_FIELD` with action `idle_at_rally`, eliminating false `MARCHING` state fabrication.
  - **Tactical Unit Actor (`TacticalUnit`):** Each recruited soldier is represented by an individual dimetric isometric actor on the 64×64 world map with ground contact foot pivot `(-12, -30)`, 2D Y-sorting, royal military gold attire modulate, and ground selection ring. Navigates using discrete cell stepping with continuous visual interpolation, honoring `TimeManager` pause and speed scaling (1x, 2x, 3x).
  - **Tactical Selection & Command Input:** Supports single selection (left-click), additive selection (Shift+left-click), and viewport drag-box selection via unprojected canvas transform. Right-click dispatches A* grid move orders to walkable in-bounds cells. Multi-unit orders compute non-overlapping target cells. ESC deselects.
  - **Spatial Formations & Control Groups:** Supports `Line`, `Column`, and `Scatter` formations computing deterministic, distinct, walkable destination slots without overlaps. Supports control groups 1..3 via `Ctrl+1/2/3` (assign) and `Shift+1/2/3` (recall) with dead unit pruning. Plain keys `1/2/3` remain reserved exclusively for simulation speed.
  - **Strategic Rally Point Banner (`ArmyMarker`):** `ArmyMarker` serves as the Strategic Rally Point Banner (`🚩 Điểm tập kết`) at `rally_cell`. Hides duplicate individual soldier body sprites when in tactical mode while preserving `visible` toggling on `soldier_count > 0` for 100% test contract compliance (TC-MOVE.24).
  - **Deferred Combat Extensions:** Field melee/ranged combat, enemy tactical units on map, tactical AI, and direct siege operations remain deferred to Package 1X. Existing `BattleResolver` and `BattleCampaignManager` remain authoritative for offensive campaigns and raids.

---

## 2. Deferred & Excluded Scope for MVP
| Feature | GDD Section | Status for MVP | Rationale |
|---|---|---|---|
| Automation Graph Delay & Repeat Nodes | Phần VII | Deferred | Bounded MVP node set; timer queues deferred to future package |
| Complex family trees & genetics | Phần IV | Deferred | Replaced by deterministic immigration system |
| Real-time physical tactical combat | Phần VII | Simplified | Abstract BattleResolver with deterministic factors |
| Cosmetic Legacy store | Phần IX | Post-MVP | Preserves focus on core simulation and save/load |
| Steam integration / Cloud save | Phần XVIII | Excluded | Offline-first PC requirement |
| Multiplayer / Co-op | Phần I | Excluded | Single-player offline specification |
