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
  - **Victory Hold:** All prosperity criteria ($\text{Population} \ge 30$, $\text{Food} \ge 500$, $\text{Treasury} \ge 1000$, $\text{Stability} \ge 80\%$, $\text{Morale} \ge 75\%$, $\text{Technologies} \ge 3$) must be maintained for 5 consecutive game-days (120 game-hours). If any metric drops below threshold, the 5-day timer resets to 0.

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
  - **Final Roster Lifecycle Patch & Closure (Closure Gate):**
    - *Recruitment Read-Only Purity & Base Recruitment:* `PlayerArmyManager.can_recruit()` is strictly side-effect free (zero state mutations on 0 soldiers). Guards movement state checks with `if soldier_count > 0: if current_cell != rally_cell: return {"can_recruit": false, "reason": "Quân đội đang dã chiến ngoài thành..."}`. Because an army recruited at base without a manager legitimately settles to `IDLE_AT_FIELD` at `rally_cell` under Invariant A, checking `current_cell != rally_cell` correctly allows recruitment at base while rejecting recruitment when deployed in the field.
    - *Recruitment Without Tactical Manager Safe Settlement:* `recruit()` strictly preserves atomic resource transactions. When recruitment succeeds without a tactical manager, the army settles to `IDLE_AT_FIELD` at `rally_cell` via `get_settled_state_for_cell(current_cell)`, strictly preventing a false `GARRISONED` publication.
    - *Tactical Manager Detachment/Re-attachment Consistency:* In `set_tactical_military_manager(mgr)`, detaching the manager (`mgr == null`) immediately transitions a non-empty garrisoned army to `IDLE_AT_FIELD` via `sync_state_from_tactical()`. Re-attaching a valid manager restores `GARRISONED` once all units are verified settled at base.
    - *Symmetric Detachment & Roster Cleanup:* Detaching or replacing a manager (via `PlayerArmyManager.set_tactical_military_manager` or `TacticalMilitaryManager.set_player_army_manager`) symmetrically unbinds signal subscriptions (`army_changed`, `tactical_state_updated`), clears back-references with recursion protection, and cleans the detached manager's roster (`clear_all_units()`), eliminating ghost units. `TacticalMilitaryManager._on_army_changed()` and `sync_with_player_army()` strictly guard with `player_army_mgr.get("tactical_military_mgr") == self`, preventing detached managers from recreating units in response to subsequent army changes.
    - *Direct `deserialize({})` and Ghost Unit Cleanup:* Calling `deserialize({})` directly on `PlayerArmyManager` explicitly invokes `tactical_military_mgr.clear_all_units()`, cleanly destroying any active/moving tactical units immediately and leaving zero ghost units.
    - *Zero-Soldier Shortcut Emptiness Verification:* Both `get_settled_state_for_cell()` and `sync_state_from_tactical()` verify that `tactical_military_mgr.get_all_units().is_empty()` before allowing a zero-soldier army to claim `GARRISONED`, returning `IDLE_AT_FIELD` if stale units remain in the manager.
  - **Tactical Unit Actor (`TacticalUnit`):** Each recruited soldier is represented by an individual dimetric isometric actor on the 64×64 world map with ground contact foot pivot `(-12, -30)`, 2D Y-sorting, royal military gold attire modulate, and ground selection ring. Navigates using discrete cell stepping with continuous visual interpolation, honoring `TimeManager` pause and speed scaling (1x, 2x, 3x).
  - **Tactical Selection & Command Input:** Supports single selection (left-click), additive selection (Shift+left-click), and viewport drag-box selection via unprojected canvas transform. Right-click dispatches A* grid move orders to walkable in-bounds cells. Multi-unit orders compute non-overlapping target cells. ESC deselects.
  - **Spatial Formations & Control Groups:** Supports `Line`, `Column`, and `Scatter` formations computing deterministic, distinct, walkable destination slots without overlaps. Supports control groups 1..3 via `Ctrl+1/2/3` (assign) and `Shift+1/2/3` (recall) with dead unit pruning. Plain keys `1/2/3` remain reserved exclusively for simulation speed.
  - **Strategic Rally Point Banner (`ArmyMarker`):** `ArmyMarker` serves as the Strategic Rally Point Banner (`🚩 Điểm tập kết`) at `rally_cell`. Hides duplicate individual soldier body sprites when in tactical mode while preserving `visible` toggling on `soldier_count > 0` for 100% test contract compliance (TC-MOVE.24).
  - **Package 1X: Tactical Combat, Enemy Military AI & Field Siege Operations:**
    - *Real-Time Tactical Combat Mechanics:* Tactical units possess data-driven combat stats: `health` (100.0), `max_health` (100.0), `attack_damage` (25.0), `attack_range` (1 for melee), `attack_cooldown` (1.2s), `is_alive`, and `faction_id`. Melee range uses Manhattan distance checking. Combat progress steps discretely via `advance_combat(delta, speed_mult, nav)` during `TacticalMilitaryManager.advance_movement()`, respecting `TimeManager` pause and speeds. Units draw visual health bars and 0.15s damage flash overlays. When target dies or becomes invalid, units cleanly disengage to `OrderState.IDLE`.
    - *Strict 1:1 Casualty Parity:* When a player tactical unit is defeated in tactical combat (`unit_defeated`), `PlayerArmyManager.on_tactical_unit_killed()` decrements `soldier_count` authoritatively and emits `army_changed`. If `soldier_count` reaches 0, the army normalizes to `GARRISONED` at `rally_cell`.
    - *Enemy Tactical Units & Crimson Modulate:* Hostile units extend `TacticalUnit` (`EnemyTacticalUnit`) and are visually distinguished by crimson sprite modulate `Color(0.95, 0.3, 0.3, 1.0)`.
    - *Deterministic Enemy AI State Machine:* Follows `HOLD`, `PATROL`, `ACQUIRE_TARGET`, `PURSUE`, `ATTACK`, and `RECOVER_RETREAT`. Targets the nearest living player unit using Manhattan distance with alphabetical ID tie-breaking. Upon signing a peace treaty, hostilities immediately cease and units transition to `RECOVER_RETREAT`.
    - *Enemy Military Management:* `EnemyMilitaryManager` maintains an authoritative roster of hostile entities, iterates over units in sorted alphabetical ID order for determinism, and handles distinct-cell spawn allocation via outward spiral search.
    - *Field Siege Operations & Objectives:* `SiegeObjectiveActor` represents capturable outposts with 300.0 durability, isometric health bars, and defender garrisons. `FieldSiegeManager` gates siege operations on active hostile factions at war with assembled field forces outside garrison perimeter (`dist > 5`). Launching a siege mobilizes defenders around the objective. Capturing the objective reduces faction military power (-20) and awards plunder (+60 Gold, +40 Food, +20 Metal). Coexists seamlessly alongside abstract `BattleCampaignManager`.
    - *Persistence & Schema Validation:* Save data integrates `"enemy_military"` and `"field_siege"` under schema version 1. Malformed or invalid data fails closed before applying world state; legacy saves without these sections load cleanly with safe defaults.
  - **Package 1X Final Gameplay Integration & Persistence Closure:**
    - *Canonical Resource Economy (Fix C):* Replaced invalid resource key `"iron"` with authoritative `EconomyConfig.RES_METAL` (`"metal"`) across `FieldSiegeManager.PLUNDER_REWARDS` and all tests. Reward delivery integrates with `ResourceManager.add_resource()`, bounds intake by warehouse storage capacity, and guarantees roundtrip preservation in save files and economy UI without unregistered keys.
    - *Deterministic Outpost Registration (Fix A1):* `WorldView` initializes visible, persistent enemy outpost objectives for active rival factions (`rival_military`, `rival_merchant`, `neutral_tribe`) at deterministic, walkable, in-bounds locations (`distance > 15` from base rally) avoiding existing buildings, blocked terrain, citizens, and player units. Ensures exactly one objective per faction.
    - *Idempotent Force Spawning & War Lifecycle (Fix A2-A4):* Connected `FactionManager.war_declared` to `_on_faction_war_declared(faction_id)`. Spawns hostile defenders around the faction outpost idempotently. Repeated war signals, world simulation updates, and save/load cycles never create duplicate forces or duplicate objectives. Simulation advancement respects `TimeManager` pause and speed multipliers.
    - *Peace Treaty & Cessation of Hostilities (Fix A5):* Connected `FactionManager.peace_signed` to `_on_faction_peace_signed(faction_id)`. Automatically disengages player attacking units, cancels active sieges against that faction, and commands enemy forces to cease hostilities and retreat.
    - *Player-Facing Siege Initiation & Feedback (Fix A6):* Right-clicking an enemy outpost actor checks siege status; if not under active siege, tests `FieldSiegeManager.can_launch_field_siege()`. On success, launches the siege and issues attack orders to selected units. On rejection, emits localized Vietnamese HUD banners explaining why the action was disallowed without issuing premature attack orders.
    - *Strict Siege Eligibility & Damage Immunity (Fix B):* Outpost actors enforce `@export var is_under_active_siege: bool = false`. Attacks prior to launching an active siege are rejected fail-closed; damage calls return early without deducting health or emitting signals. Non-hostile, inactive, captured, or destroyed outposts reject siege launches. Resolves victory, defeat, and withdrawal exactly once.
    - *Fail-Closed Persistence & Atomic Deserialization (Fix D):* `SaveManager.validate_save_data()` deeply validates `enemy_military` (unit IDs, coordinates, health/max_health bounds, string/int order states, paths) and `field_siege` (objective IDs, coordinates, health, garrison, active siege references and statuses). Both `EnemyMilitaryManager.deserialize()` and `FieldSiegeManager.deserialize()` stage all entities and validate them fully before clearing live state; on error, they return `false` without mutating live structures. `TacticalUnit` and `EnemyTacticalUnit` safely recover unresolved target references to `OrderState.IDLE`.
    - *Patrol Perimeter Return Behavior (Fix E):* `EnemyTacticalUnit._ai_tick_patrol()` uses `GridNavigation` to navigate back to `patrol_origin` when outside `patrol_radius`, or transitions to `HOLD` if navigation is obstructed.
  - **Package 1X Final Enemy Spawn, Occupancy & Siege Retry Fix:**
    - *Authoritative Spawn-Slot Entity Exclusion Policy:* `EnemyMilitaryManager.get_authoritative_occupied_cells()` collects occupied cells across all live world entities: registered siege objective cells, living enemy units, living player tactical units, living citizens (using safe `cit.has_method("is_alive")` / `cit.call("is_alive")` check), and building footprint tiles. `is_cell_spawn_eligible()` verifies that candidate coordinates are in bounds, walkable per `GridNavigation`, not water tiles, and not present in the authoritative occupied cell set.
    - *Objective Cell Overlap Immunity:* `_find_distinct_walkable_cells()` accepts `exclude_center: bool = false`. Initial war deployment in `WorldView._on_faction_war_declared()` and siege defender placement in `FieldSiegeManager.launch_field_siege()` both pass `exclude_center = true`, guaranteeing that enemy units are never spawned on an outpost's cell.
    - *Objective Targeting Click Prioritization:* In `WorldView._unhandled_input()`, exact-cell objective clicks (`obj_target != null and obj_target.current_cell == cell`) are given strict precedence over fuzzy adjacent enemy targeting. This guarantees that clicking an outpost cell is never intercepted by an enemy unit standing adjacent to it.
    - *Single Explicit Distinction Between Field Forces & Garrison Defenders:*
      - `EnemyTacticalUnit` tracks `@export var is_garrison_defender: bool = false` and `@export var assigned_objective_id: String = ""`, preserved across save/load serialization.
      - `FieldSiegeManager.launch_field_siege()` first gathers living defenders already assigned to the objective. If living defenders are fewer than `objective.garrison_count`, it attempts to assign eligible unassigned faction units nearby before spawning only the missing count (`needed = max(0, obj.garrison_count - living_defenders.size())`).
      - Mobilized defenders are assigned `OrderState.HOLD` and patrol origin at the objective cell.
      - On `VICTORY`, surviving defenders belonging to the captured outpost are commanded to `RECOVER_RETREAT` and despawn (`retreat_and_despawn()`), while `obj.defending_unit_ids` is cleared.
      - Resolving siege outcomes (`_resolve_siege_outcome`) is strictly guarded against re-entrancy (`record.get("status") != "active"`).

  - **Package 1Y: Automation Graph Delay & Repeat Nodes:**
    - *Delay Clock Convention & Bounded Scheduling:*
      - Delay nodes specify `duration_hours` strictly bounded between 1 and 720 game hours (up to 30 game days). Values $\le 0$, $> 720$, or non-integers are rejected fail-closed.
      - Scheduled continuations calculate target simulation hours using the canonical formula `due_total_hours = (current_day - 1) * 24 + current_hour + duration_hours`.
      - Target day and hour are derived deterministically: `due_day = int(floor(float(due_total_hours) / 24.0)) + 1` and `due_hour = due_total_hours % 24`. This cleanly handles midnight roll-overs and season/year boundaries.
      - Minimum 1-hour delay cannot execute in the same simulation hour as its scheduling tick; it resumes on the next eligible simulation hour tick.
      - Paused simulation (`TimeManager.is_paused`) freezes continuation execution.
    - *Continuation Queue Limits & Lifecycle Safety:*
      - Enforces strict queue bounds: global cap `MAX_GLOBAL_PENDING_CONTINUATIONS = 50` and per-program cap `MAX_PROGRAM_PENDING_CONTINUATIONS = 10`. Scheduling attempts exceeding these limits fail closed with diagnostic error codes.
      - Continuations are executed in deterministic order: sorted by `due_total_hours` ascending, then by program priority descending, and finally by stable ID.
      - Deleting a program automatically purges all pending continuations for that program. Disabled programs skip continuation resumes without throwing errors.
      - Each continuation record can only execute once and is atomically removed from the pending queue upon resumption.
    - *Repeat Node Semantics & Execution Budget Bounding:*
      - Repeat nodes specify `count` strictly bounded between 1 and 20 iterations. Values $\le 0$, $> 20$, or non-integers are rejected fail-closed.
      - Employs a dual-output model: Slot 0 `body` for the iteration body, and Slot 1 `completed` for post-loop downstream flow.
      - Graph cycle detector continues strictly rejecting circular connections and back-edges, preserving the Directed Acyclic Graph (DAG) invariant while providing finite loop capability.
      - Execution budget safety: increments `steps` on each step through the loop body, strictly honoring `MAX_STEPS_PER_RUN = 60` across all iterations combined. If budget is exhausted, execution halts safely with an informative diagnostic log.
    - *Visual Editor & Side-Effect-Free Dry Run:*
      - Visual editor features `AddDelayBtn` and `AddRepeatBtn` in the palette with Vietnamese labels ("⏳ Trì hoãn", "🔁 Lặp lại").
      - Graph node inspector provides live SpinBox controls updating node params with immediate label refresh.
      - Dry-run simulation produces detailed trace logs (explaining expected continuation resume times and loop iterations) without modifying citizen roles, altering resources, or enqueuing persistent continuations.
    - *Save/Load Persistence & Schema Version Compatibility:*
      - Schema version remains 1. The `"automation"` payload persists `pending_continuations` alongside existing graph data.
      - `SaveManager.validate_save_data()` enforces deep fail-closed validation on all continuation records (validating types, ID strings, program IDs, node IDs, integer duration 1–720, due_day $\ge 1$, due_hour 0–23, and due_total_hours $\ge 0$).
      - Legacy saves lacking `pending_continuations` pass validation and load cleanly with an empty queue.
      - Double-load idempotency is verified with zero duplicated continuation records.
    - *Final Repeat/Delay Lifecycle & Persistence Fix:*
      - *Repeat + Delay Interleaving:* When a Delay node is encountered inside a Repeat loop body, it schedules a continuation tagged with `repeat_node_id`, `repeat_iteration`, `repeat_count`, and `steps_used`. The Repeat loop suspends immediately without executing subsequent iterations or triggering the `completed` branch prematurely.
      - *Exact Post-Delay Resumption:* Resuming from a continuation restarts execution directly at `resume_node_id` (post-delay actions only, skipping pre-delay actions and Trigger). Once the resumed iteration completes, the loop advances to subsequent iterations (`repeat_iteration + 1` up to `repeat_count`), restarting each fresh from the top of the Repeat body. The `completed` branch fires exactly once after all iterations complete.
      - *Fresh Condition Evaluation per Iteration:* Each loop iteration allocates its own empty `iter_memo_bool = {}`, preventing stale condition evaluation results from bleeding across iterations and ensuring dynamic simulation changes (such as fluctuating resource stocks) are re-evaluated fresh each iteration.
      - *Nested Repeat Validation Rejection:* `AutomationGraphValidator` explicitly traverses body branches to reject nested Repeat structures fail-closed with clear diagnostics.
      - *Step Budget Bounding Across Resumptions:* Preserves `steps_used` across scheduled continuations, enforcing that logical program executions cannot exceed `MAX_STEPS_PER_RUN = 60` across delayed iterations combined.
      - *Deep Validation & Atomic Fail-Closed Deserialization:* Static `AutomationManager.validate_automation_data()` and `validate_pending_continuations()` enforce non-empty unique continuation IDs, valid programs and nodes, due-time consistency (`due_total_hours == (due_day - 1) * 24 + due_hour`), Repeat metadata matching configured node counts, and queue limits. `AutomationManager.deserialize()` validates first and stages all variables, returning `false` on malformed saves without clearing or mutating live programs, logs, or continuations.
- **1.25 Package 1Z — Legacy Fund & Meta-Progression Foundation (GDD §12.3, §13.1, §13.2):**
  - **Decoupled Meta-Progression Architecture:**
    - Ephemeral world states (`user://saves/world_save.json`, schema version 1) remain decoupled from cross-world persistent progression.
    - Persistent meta-progression is maintained in a dedicated profile file (`user://legacy_profile.json`, `PROFILE_SCHEMA_VERSION = 1`) managed by `LegacyProfileManager` (`scripts/legacy/legacy_profile_manager.gd`).
  - **Authoritative Profile Data Model & Strict Invariants:**
    - Profile tracks: `profile_id: String`, `legacy_balance: int`, `lifetime_legacy_earned: int`, `lifetime_legacy_spent: int`, `claimed_rewards: Dictionary`, `unlocked_achievements: Dictionary`.
    - Enforces two non-negotiable mathematical invariants fail-closed:
      1. `legacy_balance == lifetime_legacy_earned - lifetime_legacy_spent`.
      2. `sum(claimed_rewards[r].amount) == lifetime_legacy_earned`.
    - Rejects negative numbers, floating-point inaccuracies, unknown reward sources, and empty/mismatched reward IDs fail-closed before any mutation.
  - **Atomic File Persistence & Automatic Corruption Recovery:**
    - Employs atomic write sequence: writes serialized JSON to `user://legacy_profile.json.tmp`, rotates existing profile to `.bak`, and renames `.tmp` to `.json`.
    - Automatic `.bak` recovery: if the primary file is corrupted or missing, automatically falls back to `.bak`.
    - Fail-closed corrupt handling: if both primary and backup files are corrupted, `load_profile()` returns `success: false` and preserves live in-memory state without destructive resets to 0.
  - **Centralized Exactly-Once Reward-Claim API:**
    - `claim_reward(reward_id, source, amount, world_id, extra_details)` enforces at-most-once reward grants. Duplicate claim attempts with an already-recorded `reward_id` return `success: false`, award `0` points, and preserve balance.
    - Atomic rollback: if disk write fails during claim, staged memory mutations are rolled back cleanly to preserve disk-memory symmetry.
  - **Victory Reward Integration & Single-Source Invariant (FIX-1Z-A):**
    - `VictoryManager` connects to `LegacyProfileManager` with world-scoped key: `victory_<world_id>`.
    - Achieving Prosperity Victory after a continuous 5-day hold qualifies for exactly 100 Legacy points via the authoritative victory claim.
    - To eliminate double-award exploits (200 points instead of 100), the `prosperity_victory` achievement awards 0 direct points (`reward_legacy: 0`, `reward_status: "deferred"`), ensuring that 1 victory grants exactly 100 Legacy Fund total across victory claim and achievement unlock.
    - Loading an earlier world save where victory is reached again checks profile claimed records; duplicate reward claims are strictly rejected with 0 points awarded.
  - **Transactional Achievement Foundation & Memory Rollback (FIX-1Z-B):**
    - `unlock_achievement()` validates achievement ID against registry, stages unlock and claim records, and saves atomically.
    - If `save_profile()` fails on disk, in-memory state (unlocked dictionary, claimed rewards, balances) is rolled back completely.
    - Never fabricates unnecessary `claim_reward` records when `reward_legacy == 0`.
  - **Unique Persistent World IDs & Save Migration (FIX-1Z-C):**
    - Eliminated seed-only ID collisions (`world_<seed>`) by introducing `WorldView.generate_unique_world_id()` (timestamp + microsecond + seed + counter + salt).
    - Distinct playthroughs sharing the same seed receive unique world IDs, allowing legitimate victory claims across each world.
    - Legacy saves lacking `world_id` are automatically migrated on load and immediately persisted to disk. If migration persistence fails, victory claims are gated fail-closed (`is_world_id_persisted == false`).
  - **Fail-Closed Profile Initialization & UI State Propagation (FIX-1Z-D):**
    - Explicit profile states: `STATUS_UNINITIALIZED`, `STATUS_NEW_PROFILE`, `STATUS_LOADED`, `STATUS_RECOVERED_FROM_BACKUP`, `STATUS_UNAVAILABLE`.
    - If both primary and backup files are corrupted, `load_profile()` marks status `STATUS_UNAVAILABLE`, preserves corrupt files on disk without wiping to 0, blocks all reward claims and unlocks, and propagates the error state to `MainMenu` and `InGameHUD`.
  - **Deferred Surplus Treasury Conversion:**
    - Extension point `convert_surplus_treasury()` returns `status: "deferred"`, `converted: false`, 0 points awarded, 0 gold deducted.
    - Explicitly deferred pending authoritative design decisions for conversion formula, stability thresholds, and exchange rates per GDD §13.2.
  - **UI Reflection:**
    - Main menu (`MainMenu`) displays persistent Legacy balance (`LegacyFundLabel`) updating automatically on profile load or balance changes, displaying `[Lỗi Dữ Liệu]` when profile is unavailable.
    - HUD victory panel (`VictoryPanel`) provides interactive claim button (`ClaimVictoryBtn`) and status label (`LegacyStatusLabel`) reflecting authoritative profile state, disabling claims with error warning if profile is unavailable or unpersisted, and preventing duplicate claims.
  - **Second Hardening Audit: Canonical IDs, Safe Persistence & Overflow Protection (FIX-1Z-E – FIX-1Z-J):**
    - *Canonical Victory Reward IDs (FIX-1Z-E):* `VictoryManager.claim_legacy_reward()` strictly enforces canonical reward IDs (`victory_<world_id>`), discarding custom reward ID arguments to prevent exploit cycling. Gated checks synchronize `is_legacy_claimed` directly from profile state.
    - *Safe Backup Recovery & Corrupt Primary Protection (FIX-1Z-F & FIX-1Z-H):* In `LegacyProfileManager.save_profile()`, directory access is verified fail-closed, write/flush errors are checked, and `.tmp` is validated via schema inspection before replacing target. During backup rotation, `target_path` is only copied to `.bak` if it passes schema validation; corrupted primary files never overwrite valid backups.
    - *SaveManager Atomic Write Hardening (FIX-1Z-G):* In `SaveManager.save_dict_to_file()`, directory access and write/flush errors are validated; if backup copying fails (`dir.copy != OK`), the operation aborts immediately and preserves the primary file untouched; rename errors trigger backup restoration.
    - *Accurate HUD Reward Status Classification (FIX-1Z-I):* In `InGameHUD._refresh_victory_claim_state()`, decoupled `is_claimed` from `not is_reward_claimable()`, differentiating 6 independent states: already claimed ("Đã Nhận Di Sản"), profile unavailable ("Hồ Sơ Lỗi (Không Thể Nhận)"), unpersisted world ("Chưa Lưu Thế Giới"), invalid world ID ("ID Thế Giới Không Hợp Lệ"), claimable ("Nhận Di Sản (+100)"), and unmet conditions ("Chưa Đạt Điều Kiện").
    - *64-Bit Numeric Overflow Protection (FIX-1Z-J):* Enforced `MAX_SAFE_INT = 9223372036854775807` across `_is_valid_integer_val()`, `validate_profile_data()`, `claim_reward()`, and `unlock_achievement()`, rejecting any transaction or state that would overflow 64-bit integer bounds fail-closed.
  - **Third Hardening Audit: Fail-Closed Rewards, World ID Lifecycle & Backup Recovery Safety (FIX-1Z-K – FIX-1Z-N):**
    - *Removal of Non-Persistent Victory Reward Fallback (FIX-1Z-K):* In `VictoryManager.claim_legacy_reward()`, eliminated null-profile fallback that previously awarded unpersisted memory points. `profile_mgr` is strictly mandatory; if `profile_mgr == null` or unavailable, claims award 0 points, return 0, and leave `is_legacy_claimed = false`.
    - *Strict World ID Persistence Lifecycle (FIX-1Z-L):* Initialized `is_world_id_persisted: bool = false` across `VictoryManager` and `WorldView`. Freshly generated worlds cannot claim victory rewards until saved to disk at least once. `SaveManager.save_world_state()` sets `is_world_id_persisted = true` only upon confirmed write completion.
    - *Atomic Staged Backup Rotation & Recovery Safety (FIX-1Z-M):* In `SaveManager.save_dict_to_file()`, introduced staged backup rotation using temporary staging path `filepath + ".bak.tmp"`. Pre-validates existing primary save before rotating; corrupted primary saves never overwrite valid `.bak` files. Validates staged copy before replacing target `.bak`; rolls back target from `.bak` if rename fails. In `load_from_file()`, automatically recovers from `.bak` when primary is missing or corrupt, preserving separate `canonical_path` and `source_path` so subsequent migrations save to canonical paths.
    - *64-Bit Float Boundary Precision (FIX-1Z-N):* Fixed IEEE 754 float64 boundary precision bug where float representations of $2^{63}-1$ round up to $2^{63} = 9223372036854775808.0$. Defined strict bounds `FLOAT_INT64_EXCLUSIVE_UPPER = 9223372036854775808.0` and `FLOAT_INT64_INCLUSIVE_LOWER = -9223372036854775808.0`, rejecting values with `f < LOWER or f >= UPPER` in both `LegacyProfileManager` and `SaveManager`.
  - **Fourth Corrective Audit: Backup Content Verification, Recovery Failure Paths & Float64 Bounds (FIX-1Z-O – FIX-1Z-S):**
    - *Staged Backup Verification Before Replacement (FIX-1Z-O):* Both `SaveManager` and `LegacyProfileManager` reopen and validate the staged copy (`.bak.tmp`) to ensure JSON validity, schema compliance, and data equivalence against the previous primary save before replacing authoritative `.bak`. If validation fails, the staged copy is cleaned up and `.bak` is preserved untouched.
    - *Backup Replacement Rename Injection & Recovery (FIX-1Z-P):* Added `_test_inject_fail_backup_rename` and `_test_inject_fail_backup_validate` seams. Implemented temporary rollback staging (`.bak.old`) during backup replacement so rename failures restore the original `.bak` safely without corruption or data loss. Strengthened test assertions to verify actual restored data and backup recoverability.
    - *Profile Recovery, Write Rollback & Restart Isolation (FIX-1Z-Q):* Tested profile backup recovery followed by transaction save failures, proving that in-memory state rolls back cleanly and subsequent application restarts recover exact authoritative records without duplicate or lost claims.
    - *Representable Float64 Boundary Precision (FIX-1Z-R):* Corrected lower-bound tests to use `-9223372036854777856.0` ($-2^{63}-2048$, the next representable Float64 value below signed 64-bit minimum). Validated that both `LegacyProfileManager` and `SaveManager` accept inclusive lower bound ($-2^{63}$), reject $-9223372036854777856.0$, reject $2^{63}$, and accept the largest representable float below $2^{63}$ ($9223372036854774784.0$).
    - *Canonical Path Preservation During Migration (FIX-1Z-S):* Validated that loading and migrating a legacy save from `.bak` writes exclusively to `canonical_path`, preserving `.bak` byte-for-byte unchanged. Gated persisted status via `migration_save_failed` when migration writes fail.
  - **Fifth Corrective Audit: Crash-Safe Backup Journal, Strict Save Schema & Profile Restore Failure (FIX-1Z-T – FIX-1Z-V):**
    - *Crash-Safe `.bak.old` Recovery and Reconciliation (FIX-1Z-T):* In both `SaveManager` and `LegacyProfileManager`, implemented deterministic backup reconciliation (`_reconcile_backups()`). Validates primary, `.bak`, and `.bak.old` before cleaning temporary files; if `.bak` is missing or invalid but `.bak.old` is valid, promotes `.bak.old` to `.bak`; if both are valid, preserves `.bak` as the newer authoritative backup; never deletes the only known-good backup. In `load_from_file()` and `load_profile()`, extended fallback hierarchy to recover from `.bak.old` if primary and `.bak` cannot be used. Validates all filesystem operations fail-closed.
    - *Strict and Consistent World-Save Schema Validation (FIX-1Z-U):* In `SaveManager`, modified `_read_and_validate_save_file()` to unconditionally call `validate_save_data()`, rejecting syntactically valid JSON dictionaries missing `schema_version` or failing schema rules. In `save_dict_to_file()`, added upfront validation of incoming world-save data, immediately aborting without touching disk if invalid. Prevents rotating schema-invalid primaries into authoritative `.bak` files.
    - *Explicit Legacy Profile Restore-Copy Failure Injection (FIX-1Z-V):* Added dedicated test injection seam `_test_inject_fail_restore_copy` in `LegacyProfileManager`, distinct from `_test_inject_fail_rename`. Tested 11-step sequence covering profile recovery from `.bak`, simultaneous rename failure and backup restore-copy failure during subsequent transaction, verified transaction `save_failed` rejection, verified in-memory rollback, verified backup invariance, and verified full state recovery by a fresh manager instance.
  - **Sixth Corrective Audit: Profile Reset Safety, Backup Reconciliation Coverage & Exact Backup Preservation (FIX-1Z-W – FIX-1Z-Y):**
    - *Profile Reset Safety Against Backup Resurrection (FIX-1Z-W):* In `LegacyProfileManager.reset_profile()`, extended artifact cleanup to remove all 5 files (`target_path`, `.bak`, `.bak.old`, `.tmp`, `.bak.tmp`), checking remove return codes and verifying file absence on disk. If any artifact removal fails or fails disk verification, `reset_profile()` aborts fail-closed, transitions `profile_status` to `STATUS_UNAVAILABLE`, sets `initialization_error`, and returns `false`. Only transitions to `STATUS_NEW_PROFILE`, resets balances, and emits `balance_changed` when all artifacts are confirmed removed. Added test injection seam `_test_inject_fail_reset_cleanup`.
    - *Comprehensive Backup Reconciliation Test Coverage (FIX-1Z-X):* Added dedicated test suites for both `SaveManager` and `LegacyProfileManager` verifying both core reconciliation cases:
      - Case A: Invalid/corrupt `.bak` + valid `.bak.old`: Verifies data recovery from `.bak.old`, promotion of `.bak.old` to `.bak` upon subsequent save, removal of old file, and restart recovery from promoted `.bak`.
      - Case B: Both `.bak` and `.bak.old` valid: Verifies precedence of `.bak` over `.bak.old`, removal of obsolete `.bak.old` upon subsequent save, preservation of `.bak`, and restart recovery.
    - *Byte-for-Byte Exact Backup Preservation (FIX-1Z-Y):* Strengthened profile restore failure test to capture `PackedByteArray` before failure and compare against backup bytes after failure, verifying byte-for-byte exact preservation of `.bak`. Updated test cleanup helpers to purge `.bak.old` and `.bak.tmp`.
  - **Seventh Corrective Audit: Missing Primary Save Handling & Genuine Reset-Cleanup Failure Injection (FIX-1Z-Z – FIX-1Z-AA):**
    - *Guarded Primary Save Removal (FIX-1Z-Z):* In `LegacyProfileManager.save_profile()`, isolated `target_path` removal into an explicit block strictly guarded by `if FileAccess.file_exists(target_path):`. When saving after recovering from a backup without an existing primary save, removal is bypassed, allowing the validated `.tmp` file to rename cleanly to `target_path`. When `target_path` exists, verifies `dir.remove()` returns `OK` fail-closed before renaming.
    - *Genuine Reset-Cleanup Failure Injection (FIX-1Z-AA):* In `LegacyProfileManager.reset_profile()`, enhanced failure injection to intercept file removal for targeted artifacts (e.g. `_test_inject_fail_reset_cleanup_target = bak_old_path`), simulating real filesystem deletion failure (`rem_err = FAILED`) while leaving the file and its data intact on disk. Verified that the manager detects the failure, enters `STATUS_UNAVAILABLE`, reports lingering files in `initialization_error`, returns `false`, and rejects subsequent operations.
  - **Eighth Corrective Audit: Complete Profile Reset Artifact Coverage & In-Memory State Verification (FIX-1Z-AB – FIX-1Z-AD):**
    - *All 5 Artifacts Present Before Reset & In-Memory State Cleared (FIX-1Z-AB):* In `_test_fix_1z_w_reset_profile_resurrection_safety()`, ensured all five persistence artifacts (`target_path`, `.bak`, `.bak.old`, `.tmp`, `.bak.tmp`) exist simultaneously on disk and explicitly verified their existence via `FileAccess.file_exists()` before calling `reset_profile()`. Proved that all five files are deleted upon successful reset without deleting primary or `.bak` beforehand. Immediately verified that the original manager's in-memory state is cleared (`STATUS_NEW_PROFILE`, balances 0, empty claimed rewards, empty unlocked achievements, empty initialization error), and that a fresh manager instance confirms clean restart state.
    - *Achievement Reset & Non-Resurrection (FIX-1Z-AC):* Seeded the original profile with a valid unlocked achievement (`"prosperity_victory"`) and populated `.bak.old` with a distinguishable schema-valid achievement record. Verified that both original manager and fresh restart manager have `unlocked_achievements.is_empty()`, proving that achievements are reset in memory and cannot be resurrected from stale backups.
    - *Complete Partial Cleanup Failure Assertions (FIX-1Z-AD):* In the cleanup failure injection scenario, created all five persistence artifacts simultaneously on disk before calling `reset_profile()` with failure injected on `.bak.old`. Verified that `reset_profile()` returns `false`, manager status is `STATUS_UNAVAILABLE`, `initialization_error` identifies `.bak.old`, `.bak.old` survives byte-for-byte unchanged, all other four artifacts (`target_path`, `.bak`, `.tmp`, `.bak.tmp`) are successfully deleted from disk, and subsequent reward claims are rejected fail-closed.

### 1.28 Package 2A — Market Infrastructure & Settlement Commerce Integration
- **Context:** `docs/GDD.md` §7.1 lists "Chợ (Market) | 3x3 | 25 Gỗ, 10 Đá | Giao dịch", which was the sole remaining unintegrated building in the GDD blueprint catalog. GDD §11 specifies visiting merchants arriving periodically to trade goods with asymmetrical pricing.
- **Authoritative Design Decisions:**
  - **Blueprint Standard:** `market` added to `EconomyConfig.BLUEPRINTS` with 3×3 footprint, cost: 25 Wood + 10 Stone, construction time: 12.0 hours (conforming directly to the closest 3×3 civic building, Research Hall), 100 HP, 0 housing, 0 permanent workers, and 0 storage bonus.
  - **Builder Allocation:** Uses existing building system footprint dimension calculation ($\ge 3 \to 4$ builder slots).
  - **Cancellation & Demolition:** Standard 50% material refund (12 Wood, 5 Stone) and full occupancy grid clearance via `BuildingSystem`.
  - **Visiting Merchant Physical Docking:**
    - Visiting merchant caravans physically dock at an unoccupied, non-water, in-bounds perimeter cell adjacent to an active Market.
    - Represented by a lightweight `CaravanMarker` world actor with ground-contact foot pivot and Y-sorting enabled.
    - If no active Market exists, or Market is under construction, or Market perimeter is blocked: the caravan falls back to the Town Hall perimeter without crashing.
    - When multiple active Markets exist, selection is strictly deterministic (sorted by coordinate $y \times 64 + x$, then ID).
  - **Pure World Presentation Ownership:** Docking coordinates are transient world presentation state re-derived on load from current world data. No schema changes or extra fields in `TradeCaravan` or `SaveManager` were added.
  - **HUD Integration:** Build menu provides `MarketBtn` for placement; `DiplomacyPanel` identifies trade location (`Địa điểm giao thương: Chợ` vs `Địa điểm giao thương: Tòa thị chính`) while preserving existing trade APIs.
- **Explicitly Deferred & Excluded Non-MVP Proposals:**
  - *Emergency Trade Penalties (0% penalty):* Baseline trade prices remain 100% faithful to GDD §11 across both Market and Town Hall modes. No 25% price penalty or markup was added.
  - *Municipal Commercial Tax (0% tax):* No transaction remittance to town treasury.
  - *Market Keeper / Trader Citizens:* Market serves as civic infrastructure; no new citizen jobs.
  - *Dedicated Storage Buffer:* Market provides 0 storage bonus per GDD §7.1.

### 1.29 Package 2B — Citizen Skill Progression & Vocational Specialization (GDD §6.2, §6.3, §6.4, §6.5, §14.4)
- **Problem:** Citizens possessed job roles, workplace assignments, and need decay, but lacked vocational proficiency progression. All citizens performed labor at identical flat baseline rates regardless of labor history, violating GDD §6.5 ("Kỹ năng nghề tăng dần thông qua công việc thực tế... Trong MVP, chỉ cần một hệ số hiệu quả đơn giản, có giới hạn trên").
- **Authoritative Data Model & Bounded Thresholds:**
  - Implemented `CitizenSkillData` (`scripts/entities/citizen_skill_data.gd`) tracking individual cumulative XP across six vocational categories:
    - `farming` (Farmer)
    - `woodcutting` (Woodcutter)
    - `mining` (Miner, Quarryman)
    - `smithing` (Smith)
    - `building` (Builder)
    - `hauling` (Hauler)
  - Canonical level progression derived from cumulative XP with strictly bounded multipliers:
    - Level 1 (Novice): $0\text{ XP}$ $\to 1.00\times$ (Starting baseline)
    - Level 2 (Apprentice): $100\text{ XP}$ $\to 1.08\times$ (+8%)
    - Level 3 (Journeyman): $300\text{ XP}$ $\to 1.16\times$ (+16%)
    - Level 4 (Expert): $600\text{ XP}$ $\to 1.25\times$ (+25%)
    - Level 5 (Master): $1000\text{ XP}$ $\to 1.35\times$ (+35% approved maximum cap)
  - XP is strictly clamped to $[0.0, 1000.0]$.
- **Real Work Only XP Attribution:**
  - *Production:* $+10\text{ XP}$ awarded to the specific crafting worker only upon successful cycle completion committing goods to workplace output buffer (`produced_qty > 0`). Zero XP on failure, full buffer, or missing recipe inputs.
  - *Building:* $+5\text{ XP}$ per game-hour of actual active construction labor contributed, preserving fractional progress accurately. Zero XP for assignment without progress.
  - *Hauling:* $+10\text{ XP}$ awarded to the specific delivering hauler only upon genuine cargo deposit into storage (`delivered_amount > 0`). Zero XP for empty trips, pickup, or interrupted journeys.
  - *Zero Passive XP:* Idle, sleeping, eating, and wandering states award exactly $0\text{ XP}$. Repeated completion callbacks are strictly idempotent.
- **Gameplay Effect Integration:**
  - *Production:* Applied worker-specific multiplier to work rate (`effective_work = delta_hours * skill_mult`) in `CitizenController._process_working()`, completing cycles faster and preserving integer recipe conservation without rounding loss.
  - *Building:* Builder vocational multiplier scales independent construction contribution in `_process_building_work()`, allowing multiple builders to contribute additively without compounding across workers.
  - *Hauling:* Hauler vocational multiplier scales individual movement speed (`move_speed_px * hauler_mult`, 48.0 px/s $\to$ 64.8 px/s at Master Level 5), directly accelerating logistics throughput.
- **Cross-Training & Persistence Invariants:**
  - Role reassignment preserves all accumulated vocational XP across careers; citizens retain their hard-earned mastery when switching roles.
  - Versioned JSON serialization under `citizens` array (`skills: { "farming": 340.0, ... }`) without schema version bumping. Legacy saves lacking skill data deserialize cleanly with Level 1, 0 XP defaults. Malformed or tampered inputs clamp fail-closed.
- **UI Reflection:**
  - Enhanced `CitizenInspectPanel` in `scenes/ui/hud.tscn` and `scripts/ui/hud.gd` with dynamic vocational skill name, level badge (`Nông nghiệp — Cấp 3 (Thợ lành nghề)`), visual XP progress bar, and efficiency percentage readout (`+16%`), with dedicated maximum state for Level 5 and clean neutral status for idle/guard citizens.

### 1.30 Package 2C — Surplus Treasury Conversion & Victory Settlement Integration (GDD §13.2)
- **Problem:** When achieving a Prosperity Victory, players earned a flat +100 Legacy Points regardless of economic prosperity or accumulated wealth. GDD §13.2 specified that surplus treasury could convert to persistent Legacy Points, but deferred the exact conversion formula, reserve threshold, eligibility requirements, and recovery policies.
- **Approved & Authoritative Gameplay Rules:**
  - *Conversion Formula:*
    - Protected Gold reserve: 1,000 Gold.
    - Conversion rate: 100 surplus Gold = 1 Legacy Point.
    - Mathematical calculation:
      $$\text{surplus\_gold} = \max(0, \text{treasury\_gold} - 1000)$$
      $$\text{legacy\_awarded} = \lfloor \text{surplus\_gold} / 100 \rfloor$$
      $$\text{gold\_deducted} = \text{legacy\_awarded} \times 100$$
    - The conversion deducts only the converted gold; the 1,000 Gold reserve and unconvertible remainder are strictly preserved. Treasury balance can never become negative.
  - *Eligibility Conditions:*
    - All 5 conditions must be satisfied:
      1. Prosperity Victory achieved (`is_victory_achieved == true`).
      2. Finalized through actual victory-ending settlement flow (`finalize_victory_settlement()`).
      3. Kingdom Stability at settlement $\ge 80.0\%$.
      4. Valid, persisted unique World ID.
      5. World has not already completed treasury conversion.
  - *Collapse & Defeat Policy:*
    - Collapsed, ruined, or defeated settlements receive strictly 0 Legacy from surplus treasury conversion (`legacy_awarded = 0`, `gold_deducted = 0`).
  - *Exactly-Once Protection & Interruption Safety:*
    - Treasury conversion is strictly one-time per World ID. Reopening the summary, reloading pre-settlement save files, or calling settlement repeatedly cannot re-convert or duplicate points.
    - Transaction records are committed to persistent disk storage in `LegacyProfileManager` under `treasury_conversions` with schema: `{ world_id, original_gold, stability, gold_deducted, legacy_awarded, status, converted_at_unix }`.
    - Profile balance invariants strictly enforced: `legacy_balance == lifetime_legacy_earned - lifetime_legacy_spent`, with conversion earnings audited under `claimed_rewards` (`source = "treasury_conversion"`).
    - If disk writing or atomic validation fails, the in-memory transaction rolls back and gold is not deducted.
  - *UI Presentation:*
    - Victory panel displays Vietnamese summary:
      - Ngân khố trước chuyển đổi: `[X] Vàng`
      - Vàng được giữ lại: `[Y] Vàng` | Vàng đã chuyển đổi: `[Z] Vàng`
      - Legacy nhận được từ ngân khố: `+[N] điểm`
      - Tỷ lệ quy đổi: `100 Vàng = 1 Legacy` (Bảo lưu: `1.000 Vàng`)
      - Kết quả giao dịch: Detailed status including explicit explanations for zero surplus or stability $< 80.0\%$.
      - Settlement button updates dynamically: `Nhận Di Sản (+100)` $\to$ `Nhận Di Sản (+140)` $\to$ `Đã Nhận Di Sản`.

### 1.31 Package 2D — In-Game Player Field Guide & 30-Day Starter Manual (GDD §1.2 & §6.5)
- **Problem:** New players entering KINGDOMS UNBOUND faced a steep learning curve without in-game documentation of core mechanics, seasonal farm multipliers, vocational skill thresholds, logistics buffer saturation, or victory/Legacy formulas. Players had to rely on out-of-game documentation or trial-and-error.
- **Approved & Authoritative Gameplay Rules:**
  - *In-Game Non-Linear Field Guide:*
    - Integrated directly into the game HUD via top-right action button (`GuideHudBtn` "📖 Cẩm Nang (H)") and pause menu (`PauseMenuOverlay/GuideBtn`), accessible via hotkeys `H` and `F1`.
    - Players can open and close the guide at any time during active gameplay without leaving their current world.
    - Opening or closing the guide causes strictly zero mutation to world state: does not pause or alter `TimeManager` simulation speed or clock, does not modify resources, citizens, buildings, or Legacy profile data, and does not trigger autosaves.
    - Fully non-linear browsing across all 6 structured chapters with sidebar navigation, previous/next chapter controls, and scrollable content area.
  - *Six Structured Chapters (Natural Vietnamese):*
    - **Chương A (Khởi Đầu Vương Quốc):** Player leadership role, TopBar/BottomBar HUD inspection, simulation speed controls (⏸, 1x, 2x, 3x), starting settlement facts: exactly 24 citizens (5 farmers, 4 woodcutters, 3 builders, 3 haulers, 9 idle), 8 initial buildings (Town Hall 3×3, Storehouse 2×2, Farm 2×2, Woodcutter Camp 2×2, 4 Houses 2×2), and starting inventory (150 Food, 120 Wood, 60 Stone, 0 Ore, 20 Metal, 15 Tools, 5 Crystal, 10 Herbs, 200 Gold).
    - **Chương B (Dân Cư & Nghề Nghiệp):** Citizen vocations, idle citizen assignment, survival needs (Hunger, Fatigue, Health, Morale), 6 vocations from Package 2B (`CitizenSkillData`), real-work XP accumulation, and exact efficiency progression: Level 1 (0 XP, 1.00×), Level 2 (100 XP, 1.08×), Level 3 (300 XP, 1.16×), Level 4 (600 XP, 1.25×), Level 5 (1,000 XP, 1.35× max).
    - **Chương C (Xây Dựng & Chuỗi Sản Xuất):** Placement rules, Builder labor from 0% to 100%, workplace output buffer (Local Buffer) vs Central Storehouse distinction, crucial principle that buffered resources are unavailable for general consumption until hauled, vital role of Haulers, and workplace saturation halting production.
    - **Chương D (Hướng Dẫn 30 Ngày Đầu Tiên):** 40-day year calendar (10 days/season), seasonal farm multipliers (Spring 1.0×, Summer 1.2×, Autumn 1.0×, Winter 0.5×) with explicit notice that seasonal modifiers apply strictly to farm food (wood, stone, ore, and metal unaffected), and tactical 4-stage starter guidance (Days 1–10, 11–20, 21–30, 31–40).
    - **Chương E (Sự Kiện, Ngoại Giao & Quân Đội):** `EventManager` world events and warning banners, Faction Relations Matrix (Opinion levels, NAP, Alliances, gifts), Market trading and Caravans, Barracks soldier recruitment, daily upkeep (Food + Gold), tactical marching, and military casualty risks.
    - **Chương F (Chiến Thắng, Sụp Đổ & Di Sản):** Prosperity Victory requirements (50+ population, $\ge 80\%$ Stability, Gold target held for 5 consecutive days), collapse conditions (0 population or 0% Stability), base victory reward (+100 LP), and Package 2C Surplus Treasury conversion rules (1,000 Gold reserve, 100:1 rate, $\ge 80\%$ Stability, collapsed settlements ineligible, exactly-once idempotency per World ID).
  - *UI Geometry & Input Isolation:*
    - Full modal overlay with `mouse_filter = Control.MOUSE_FILTER_STOP` preventing click-through to underlying world tiles or unit selection.
    - Responsive layout bounded at $860 \times 490$ px inside centered container, verified non-clipping and fully enclosed at both 1280×720 and 1024×576 resolutions.

### 1.32 Package 2E — Autonomous Faction Conflict & Inter-Faction Warfare (GDD §10.1, §10.2, §10.5, §11.1)
- **Problem:** NPC factions possessed pairwise relation records and could wage wars against the player, but had no autonomous evaluation engine or campaign mechanism to declare war on each other, mobilize military campaigns against rival outposts, resolve real battles, or negotiate peace, leaving inter-faction world politics static.
- **Approved & Authoritative Gameplay Rules:**
  - *Pairwise War Declaration Criteria:*
    - Opinion threshold: `opinion <= -50.0`
    - Military power prerequisite: `initiator.military_power >= 40.0`
    - Stability prerequisite: `initiator.stability >= 30.0`
    - Relative power ratio: `initiator.military_power / target.military_power >= 0.65`
    - Casus Belli: Contextual and deterministic based on strategic goal, historical enmity, or trade route rivalry.
    - Blocked if: target or initiator is `in_exile`/`eliminated`, active NAP or Alliance exists, or an active Truce is in effect.
  - *Anti-Oscillation & Truce Invariants:*
    - Truce duration: 6 game days (`INTER_TRUCE_DURATION_DAYS = 6`).
    - Minimum war duration: 2 game days (`INTER_WAR_MIN_DURATION_DAYS = 2`).
    - Opinion hysteresis: Peace treaty grants $+20.0$ mutual opinion, raising relations from $-50.0$ to $-30.0$, preventing immediate re-flipping into war.
    - Fail-closed truce check: All declaration attempts during active truce return `PAIR_REASON_ERR_ON_TRUCE`.
  - *Campaign Execution & Real Battle Resolution:*
    - Reuses `BattleCampaignManager` and authoritative `BattleResolver.resolve_battle`.
    - No phantom troops or fabricated resources: forces scaled proportionally from current `military_power`; plundered resources strictly transferred from defender stockpile to attacker stockpile without generation from thin air.
    - Outpost damage: Attacker victory inflicts real damage to defender's regional outpost (`FieldSiegeManager`), with sacking if reduced to 0 HP.
    - Casualties deduct from both military power and faction population.
  - *War Weariness & Peace Negotiation:*
    - War weariness triggers after 12 days of war (`INTER_WAR_WEARINESS_DAYS = 12`) or when either side suffers military exhaustion (`military_power <= 20.0` or `stability <= 25.0`).
    - Signing peace terminates war, establishes 6-day truce, cancels pending inter-faction campaigns, and emits `faction_pair_peace_signed`.
  - *World & Trade Impact on Player:*
    - Complete player isolation: NPC-NPC wars never modify player opinions, player treaties, or player-targeted raids.
    - Trade caravans originating from factions currently at war incur a $+15\%$ wartime risk surcharge (`WARTIME_PRICE_SURCHARGE = 0.15`) with a guaranteed minimum +1 Gold markup on all commodities.
  - *UI & Persistence:*
    - HUD event banners display worldwide conflict announcements ("Tin Chiến Sự Thế Giới!", "Hòa Ước Đình Chiến!", "Chiến Dịch Ngoại Bang!", and battle victory/casualty reports).
    - Diplomacy Panel Section 3 dynamically lists all 3 canonical NPC-NPC pairs with color-coded status badges, 2-way opinion readouts, Casus Belli, war duration, pending campaign status, recent battle summaries, and player alliance warnings.
    - Save/Load: Full versioned persistence of inter-faction campaigns, reports, and pairwise metadata (`truce_until_day`, `war_start_day`, `casus_belli`, `war_count`, `last_battle_report`) with fail-closed schema validation in `SaveManager`.

### 1.33 Package 2G — Outpost Capture & Territorial Control (GDD §10.1, §10.5, §11.1)
- **Problem:** When an outpost was defeated in a field siege or autonomous inter-faction campaign, it remained permanently marked as dead or retained its original owner in `owning_faction_id`, failing to transfer territorial control or reflect world conquest.
- **Approved & Authoritative Design Decisions:**
  - *Authoritative Outpost Ownership Model:*
    - Tracks dynamic `owning_faction_id` (`"player"`, `"rival_military"`, `"rival_merchant"`, `"neutral_tribe"`), immutable founding `original_owner_id`, historical `previous_owner_id`, monotonic `capture_revision`, and transaction idempotency token `last_capture_tx_id`.
    - Centralized in `SiegeObjectiveActor` and coordinated by `FieldSiegeManager`.
  - *Post-Conquest State & 35% Health Recovery:*
    - Outposts are permanent map fixtures; they are never deleted or permanently dead.
    - Capturing an outpost atomically restores health to exactly $35\%$ of `max_health` (`round(max_health * 0.35)`), resets `is_alive = true`, `is_captured = true`, `is_under_active_siege = false`, and clears remaining defender units.
    - Living outposts can be sieged and recaptured indefinitely.
  - *Distinct Visual Territorial Presentation:*
    - Faction heraldry banner colors: Royal Blue (`Color(0.2, 0.45, 0.85)`) with golden pole and finials for `"player"`, Crimson Red for `rival_military`, Amber Gold for `rival_merchant`, and Forest Green for `neutral_tribe`.
    - Health bar color: Green (`Color(0.2, 0.8, 0.2)`) for player-owned outposts, Red (`Color(0.8, 0.2, 0.2)`) for hostile/NPC outposts.
    - Dynamic building name: `"Tiền Đồn Vương Quốc"` for player, `"Tiền Đồn [Faction Name]"` for factions.
  - *Combat & Campaign Integration:*
    - Player field siege victory transfers outpost to `"player"` with `tx_id = "player_siege_" + siege_id`.
    - Friendly siege prevention: Players cannot launch field sieges against outposts they already own.
    - Autonomous NPC campaigns dynamically target defender outposts, inflict siege damage on victory, sack outposts on breach ($HP \le 0.0$), and transfer ownership with unique campaign transaction IDs.
    - Collision avoidance: NPC campaigns strictly bypass outposts currently under active player siege (`is_under_active_siege == true`).
  - *Persistence & Backward Compatibility:*
    - Strict fail-closed schema validation in `SaveManager.validate_save_data()` for Package 2G metadata.
    - 100% backward compatibility for legacy saves lacking territorial control fields.
- **Explicit Scope Boundaries & Non-Goals:**
  - No 64x64 whole-map territory grid: Outposts serve as discrete territorial control nodes.
  - No new building blueprints, resources, or factions.
  - No fake player faction inserted into `FactionManager._factions` (reserved `"player"` owner ID only).
  - No faction elimination or exile solely from losing outposts.
- **1.30 Dynamic Market Pricing & Supply-Demand Economy (GDD §11.1 — Package 2H):**
  - **Dynamic Pricing Elasticity & Hard Bounds:**
    - Unit prices dynamically react to kingdom available unreserved stock and caravan inventory stock.
    - Symmetric supply pressures bounded to $[-0.10, +0.10]$ ($10\%$ pressure from local stock, $10\%$ pressure from caravan inventory).
    - Market multiplier is strictly clamped to $[0.80, 1.20]$ ($\pm 20\%$).
    - Zero RNG is used in pricing; baseline multiplier is identically $1.00$ at reference stock levels.
  - **Reference Stock Baselines:**
    - Local Kingdom reference: Sourced directly from `EconomyConfig.STARTING_RESOURCES` (`Food: 150`, `Wood: 120`, `Stone: 60`, `Metal: 20`, `Tools: 15`, `Herbs: 10`, `Crystal: 5`). Available stock queries `ResourceManager.get_available_stock(res_id)`.
    - Caravan reference: Sourced from the exact midpoint of generated inventory ranges (`Food: 45.0`, `Wood: 35.0`, `Stone: 22.5`, `Metal: 17.5`, `Tools: 10.0`, `Herbs: 17.5`, `Crystal: 4.0`).
  - **Multi-Factor Price Synthesis & Spread Invariant:**
    - Player purchase price combines base sell price, diplomatic opinion discount (up to $-20\%$), wartime route surcharge ($+15\%$), and the dynamic multiplier.
    - Player sale payout combines base buy price, diplomatic premium (up to $+20\%$), and the dynamic multiplier.
    - Guaranteed bid/ask spread: `final_sell_price >= 2`, `final_buy_price = clampi(raw_buy, 1, final_sell_price - 1)`. Caravan sell price is strictly greater than buy price by $\ge 1\text{ Gold}$ across all conditions, eliminating arbitrage loops and guaranteeing positive integer prices.
  - **Persistence & Backward Compatibility:**
    - Dynamic pricing recomputes deterministically from existing state. Zero schema migrations or new persisted fields required.
  - **Explicit Non-Goals & Out of Scope:**
    - No new resource types or merchant classes.
    - No NPC market keeper citizens or physical trading routes.
    - No complex stock exchange or futures trading.
    - No random price walk or 25% emergency trade penalties.

---

## 2. Deferred & Excluded Scope for MVP
| Feature | GDD Section | Status for MVP | Rationale |
|---|---|---|---|
| Dynamic Market Pricing & Supply-Demand Economy | Phần VII & XI | Implemented | Delivered end-to-end in Package 2H with deterministic [0.80, 1.20] elasticity, reference baselines, spread invariant, unified price breakdown API, HUD tooltips, and 100% save compatibility |
| Outpost Capture & Territorial Control | Phần X & XI | Implemented | Delivered end-to-end in Package 2G with persistent ownership, 35% health recovery, heraldic banners, friendly siege prevention, NPC sacking, collision avoidance, and fail-closed persistence |
| Autonomous Faction Conflict & Inter-Faction Warfare | Phần X & XI | Implemented | Delivered end-to-end in Package 2E with pairwise war/peace AI, BattleResolver campaigns, resource plunder conservation, outpost siege damage, truce cooldowns, caravan surcharges, and Section 3 UI |
| In-Game Player Field Guide & 30-Day Starter Manual | Phần I, VI & XIII | Implemented | Delivered end-to-end in Package 2D with 6 chapters, zero world mutation, input isolation, and 1280x720 / 1024x576 responsive layout |
| Citizen Skill Progression & Vocational Specialization | Phần VI & XIV | Implemented | Delivered end-to-end in Package 2B with 6 vocations, 1.00x-1.35x bounded multipliers, real-work XP, and HUD Inspector |
| Market Infrastructure & Physical Caravan Integration | Phần VII & XI | Implemented | Delivered end-to-end in Package 2A with 3x3 Market, deterministic docking, Town Hall fallback, and CaravanMarker actor |
| Automation Graph Delay & Repeat Nodes | Phần VII | Implemented | Delivered end-to-end in Package 1Y with bounded simulation clock queues |
| Persistent Legacy Fund Foundation | Phần XII & XIII | Implemented | Delivered in Package 1Z with decoupled profile, atomic persistence, exactly-once claims, and UI |
| Surplus treasury conversion to Legacy | Phần XIII | Implemented | Delivered end-to-end in Package 2C with 1,000 reserve, 100:1 rate, 80% stability gate, and exactly-once persistence |
| Complex family trees & genetics | Phần IV | Deferred | Replaced by deterministic immigration system |
| Real-time physical tactical combat | Phần VII | Implemented | Tactical combat, enemy AI & field siege delivered in Package 1X |
| Cosmetic Legacy store | Phần IX | Post-MVP | Preserves focus on core simulation and save/load |
| Steam integration / Cloud save | Phần XVIII | Excluded | Offline-first PC requirement |
| Multiplayer / Co-op | Phần I | Excluded | Single-player offline specification |
