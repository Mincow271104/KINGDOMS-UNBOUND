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
  - **Daily Simulation Pipeline Integration:**
    - Evaluated in `FactionManager.update_daily_simulation(day)` after the neutral tribe ascension check, ensuring that post-ascension goals (`consolidate_power`) are immediately respected.
    - Factions are processed in stable alphabetical order (`sorted_ids.sort()`) exactly once per daily simulation tick.
    - Emits `FactionManager.strategic_intent_evaluated(faction_id, intent_data)` for each eligible active faction. Inactive factions (`in_exile`, `eliminated`) are suppressed from standard intent emission.
    - Query APIs `get_faction_strategic_intent(faction_id)` and `evaluate_all_strategic_intents()` provide deterministic read access on demand without requiring simulation ticks.
  - **Fail-Closed & State Invariance:**
    - Unrecognized goals, statuses, or null faction references return ineligible results with explicit error reason codes without throwing exceptions or mutating faction state.
    - Evaluation is strictly side-effect free: `name`, `type`, `opinion`, `military_power`, `stability`, `resources`, `population`, `is_at_war`, `has_nap`, `has_alliance`, `strategic_goal`, and `existence_status` remain 100% invariant across evaluations.

---

## 2. Deferred & Excluded Scope for MVP
| Feature | GDD Section | Status for MVP | Rationale |
|---|---|---|---|
| Complex family trees & genetics | Phần IV | Deferred | Replaced by deterministic immigration system |
| Real-time physical tactical combat | Phần VII | Simplified | Abstract BattleResolver with deterministic factors |
| Cosmetic Legacy store | Phần IX | Post-MVP | Preserves focus on core simulation and save/load |
| Steam integration / Cloud save | Phần XVIII | Excluded | Offline-first PC requirement |
| Multiplayer / Co-op | Phần I | Excluded | Single-player offline specification |
