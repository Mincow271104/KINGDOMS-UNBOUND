# KINGDOMS UNBOUND — Authoritative Game Rules & Mathematical Formulas

## Document Overview
- **Status:** Approved Baseline (Phase 0)
- **Engine:** Godot 4.7
- **Authority:** Secondary to `MASTER_PROMPT.md` and `docs/GDD.md`.
- **Purpose:** Central definition of all mathematical formulas, simulation tick rates, resource thresholds, capacity limits, job rules, victory conditions, and collapse states.

---

## 1. Coordinate Mathematics & Map Geometry

### 1.1 Logical Grid vs. Screen Projection
- **Logical Map Dimensions:** $64 \times 64$ discrete integer cells (`Vector2i`). Valid cell bounds: $0 \le x < 64$, $0 \le y < 64$.
- **Ground Tile Geometry:** 2:1 dimetric isometric diamond, $32$ pixels wide by $16$ pixels tall ($\approx 26.565^\circ$ projection angle).
- **Depth / Y-Sorting:** World container and entities use `y_sort_enabled = true`. Entity origins are pinned strictly at the ground-contact base center.

### 1.2 Transformation Formulas

#### Grid Cell to Map-Local Coordinates (`map_to_local`)
For logical integer cell $(gx, gy)$:
$$\text{local\_x} = (gx - gy) \times 16.0$$
$$\text{local\_y} = (gx + gy) \times 8.0$$

#### Map-Local to Grid Cell Coordinates (`local_to_map`)
For map-local continuous coordinates $(lx, ly)$:
$$u = \frac{lx}{32.0} + \frac{ly}{16.0}$$
$$v = \frac{ly}{16.0} - \frac{lx}{32.0}$$
$$gx = \lfloor u + 0.5 \rfloor$$
$$gy = \lfloor v + 0.5 \rfloor$$

If $gx < 0$ or $gx \ge 64$ or $gy < 0$ or $gy \ge 64$, the coordinate is out of bounds.

---

## 2. Time & Simulation Ticks

### 2.1 Time Scale
- **1 Game Hour:** $1.0$ real second at $1\times$ speed.
- **1 Game Day:** $24$ Game Hours ($24.0$ real seconds at $1\times$).
- **1 Season:** $10$ Game Days ($240.0$ real seconds at $1\times$).
- **1 Year:** $4$ Seasons ($40$ Game Days = $960.0$ real seconds at $1\times$).
- **Time Controls:**
  - $0\times$: Pause (all simulation processes, needs, timers, and movement halt).
  - $1\times$: Normal speed.
  - $2\times$: Fast speed ($2.0\times$ delta).
  - $3\times$: Very fast speed ($3.0\times$ delta).

### 2.2 Tick Scheduling
- **Needs & State Tick:** Hourly ($1.0$ Game Hour). Citizen needs (Hunger, Fatigue, Health, Morale) update.
- **Daily Accounting Tick:** Daily at midnight ($00:00$ Game Time).
  - Food consumption deducted from aggregate stores.
  - Daily production summaries tallied.
  - Daily maintenance costs and building decay checks applied.
- **Immigration / Event Tick:** Every 3 Game Days at $06:00$.
- **Seasonal Transition Tick:** Day 11, 21, 31, and 41 at $00:00$.

---

## 3. Economy & Resources

### 3.1 Resource Types & Master Ledger
All resources are tracked using stable string/enum IDs:
1. `food` (Lương thực)
2. `wood` (Gỗ)
3. `stone` (Đá)
4. `ore` (Quặng thô)
5. `metal` (Kim loại)
6. `tools` (Công cụ)
7. `crystal` (Pha lê ma thuật)
8. `herbs` (Thảo mộc)
9. `gold` (Ngân khố / Tiền tệ)

### 3.2 Post-Settlement Starting Inventory
Configured centrally in `EconomyConfig`:
- `food`: $150$
- `wood`: $120$
- `stone`: $60$
- `ore`: $0$
- `metal`: $20$
- `tools`: $15$
- `crystal`: $5$
- `herbs`: $10$
- `gold`: $200$

### 3.3 Storage Capacities
- **Town Hall (Tòa Thị Chính):** Base capacity = $500$ items.
- **Storehouse (Kho Lương / Nhà Kho):** Base capacity = $1000$ items.
- **Local Workplace Buffers:**
  - Farm: Input $0$, Output buffer $50$ food.
  - Woodcutter Camp: Input $0$, Output buffer $40$ wood.
  - Quarry: Input $0$, Output buffer $40$ stone.
  - Mine: Input $0$, Output buffer $40$ ore.
  - Workshop: Input buffers from central stock (atomic check); Dual output buffers: $40$ metal, $40$ tools.
- **Storage Conservation Rule:** Items in local workplace buffers do not count toward central construction availability until physically transported by Haulers to a Storehouse or Town Hall.
- **Atomic Reservation:** `ResourceManager.reserve_resource(id, amount) -> bool` guarantees materials cannot be double-spent across competing build or crafting orders.

---

## 4. Buildings & Footprints

### 4.1 Settlement Structures
| Building | Footprint (Grid) | Footprint (Local Diamond) | Starting Count | Function & Capacity |
|---|---|---|---|---|
| **Town Hall** | $3 \times 3$ cells | $96 \times 48$ px base | 1 | Settlement hub, $500$ storage, immigration focal point |
| **House** | $2 \times 2$ cells | $64 \times 32$ px base | 4 | $6$ citizens housing cap each ($24$ total starting cap) |
| **Farm** | $2 \times 2$ cells | $64 \times 32$ px base | 1 | Base output $5.0$ Food/farmer/day, max 5 workers |
| **Woodcutter Camp** | $2 \times 2$ cells | $64 \times 32$ px base | 1 | Base output $5.0$ Wood/worker/day, max 4 workers |
| **Storehouse** | $2 \times 2$ cells | $64 \times 32$ px base | 1 | $1000$ item general resource storage |
| **Watchtower** | $1 \times 1$ cell | $32 \times 16$ px base | 0 | 20 Wood + 15 Stone, vision radius 15, scouting/defense |
| **Quarry** | $2 \times 2$ cells | $64 \times 32$ px base | 0 | 15 Wood + 5 Tools, max 4 miners, output stone |
| **Mine** | $2 \times 2$ cells | $64 \times 32$ px base | 0 | 20 Wood + 10 Stone, max 4 miners, output ore |
| **Workshop** | $2 \times 2$ cells | $64 \times 32$ px base | 0 | 20 Wood + 15 Stone + 5 Metal, max 4 smiths (2 smelt, 2 craft) |
| **Research Hall** | $3 \times 3$ cells | $96 \times 48$ px base | 0 | 25 Wood + 10 Stone, unlocks technological research |
| **Barracks** | $3 \times 3$ cells | $96 \times 48$ px base | 0 | 25 Wood + 20 Stone + 5 Metal, 2 guard sentry posts, gates Guard role |
| **Palisade** | $1 \times 1$ cell | $32 \times 16$ px base | 0 | 4 Wood + 2 Stone, 3.0h build time, solid obstacle, grants fortification level |

### 4.2 Workshop Recipes
- **Smelt Metal (Luyện Kim Loại):** 2 Ore $\to$ 1 Metal (3.0h duration, buffer capacity 40).
- **Craft Tools (Rèn Công Cụ):** 2 Metal + 1 Wood $\to$ 1 Tool (3.0h duration, buffer capacity 40).

### 4.3 Building Costs & Construction States
- **Construction States:** `Unbuilt` $\to$ `Placing` $\to$ `UnderConstruction` $\to$ `Active` $\to$ `Paused` $\to$ `Damaged` $\to$ `Destroyed`.
- **Occupancy Rule:** A building footprint of size $W \times H$ occupies cells $(gx + i, gy + j)$ for $0 \le i < W$ and $0 \le j < H$. All footprint cells must be buildable, walkable terrain, and unreserved.

### 4.4 Fortifications & Settlement Defense
- **Palisade (Tường Rào):** 1x1 footprint solid obstacle unwalkable by citizens (`is_cell_walkable == false`).
- **Fortification Level Calculation:**
  - Calculated deterministically by `BuildingSystem.calculate_fortification_level(world_data)` and `BattleResolver.calculate_settlement_fortification_level(world_data)`.
  - Only `state == "active"` palisades count (under_construction and damaged palisades are ignored). Duplicate palisade records sharing the same cell are deduplicated.
  - Threshold mapping:
    - $0$ active palisades: Level 0 (no bonus)
    - $1$ to $4$ active palisades: Level 1 (+30% defender combat score)
    - $5$ to $9$ active palisades: Level 2 (+60% defender combat score)
    - $10+$ active palisades: Level 3 (+90% defender combat score, clamped maximum)

---

## 5. Citizens, Jobs & Needs

### 5.1 Starting Population Distribution (24 Citizens)
- **Farmers:** 5 (Assigned to Starter Farm)
- **Woodcutters:** 4 (Assigned to Starter Woodcutter Camp)
- **Builders:** 3 (Assigned to construct/repair projects)
- **Haulers:** 3 (Assigned to transport goods to storage)
- **Idle / Available:** 9 (Unassigned reserve pool)

### 5.2 Citizen Needs & Decay Rates
Each citizen possesses normalized stats ($0.0$ to $100.0$):
1. **Hunger (Cơn đói):**
   - $0.0$ = Fully sated, $100.0$ = Starving.
   - Increases at $+4.167$ per game-hour when active (reaches $100$ in 24 hours without food).
   - Daily consumption target: $0.8$ Food per citizen per day.
   - Citizens seek food from Town Hall/Storehouse when Hunger $\ge 60.0$.
2. **Fatigue (Mệt mỏi):**
   - $0.0$ = Fully rested, $100.0$ = Exhausted.
   - Increases at $+4.0$ per game-hour of labor.
   - Citizen seeks rest at their assigned House when Fatigue $\ge 80.0$.
   - Recovers at $-12.5$ per game-hour while resting (8 hours for full recovery).
3. **Health (Sức khỏe):**
   - Baseline $100.0$.
   - Drops at $-5.0$ per day during starvation (Hunger $= 100$).
   - Drops during illness, cold, or attacks.
   - Citizen dies if Health reaches $0.0$.
4. **Morale (Tinh thần):**
   - Baseline $70.0$ ($0.0$ to $100.0$).
   - Drops when hungry, homeless, or under high taxation.
   - Directly impacts work productivity modifier: $\text{Productivity} = 0.5 + 0.5 \times (\text{Morale} / 100.0)$.

### 5.3 Job State Machine
A job transitions through:
`Available` $\to$ `Reserved` $\to$ `In Progress` $\to$ `Completed` / `Failed` / `Cancelled`.
- Target unreachable: Worker drops reservation and returns to `Idle`.
- Worker reassigned: Worker cleans up active job reservations before switching tasks.

---

## 6. Seasons & Climate

### 6.1 Calendar
- **Year Length:** 40 Game Days.
- **Season Length:** 10 Game Days.
- **Sequence:**
  1. **Spring (Mùa Xuân):** Days 1–10. Farm modifier $= 1.0\times$. Normal climate.
  2. **Summer (Mùa Hè):** Days 11–20. Farm modifier $= 1.2\times$. High warmth.
  3. **Autumn (Mùa Thu):** Days 21–30. Farm modifier $= 1.0\times$. Harvest season.
  4. **Winter (Mùa Đông):** Days 31–40. Farm modifier $= 0.5\times$. Firewood consumption active; farm output halved.

---

## 7. Victory & Collapse Rules

### 7.1 Prosperity Victory (Chiến Thắng Thịnh Vượng)
To achieve Prosperity Victory, the settlement must simultaneously satisfy all of the following conditions continuously for **5 consecutive game-days (120 game-hours)**:
1. **Population:** $\ge 30$ living citizens.
2. **Food Reserves:** $\ge 500$ units in storage.
3. **Treasury:** $\ge 1000$ Gold in treasury.
4. **Settlement Stability:** $\ge 80\%$.
5. **Average Morale:** $\ge 75\%$.
6. **Technologies Unlocked:** $\ge 3$ completed technologies.

If any condition lapses, the hold timer immediately resets to 0.

### 7.2 Settlement Collapse (Sụp Đổ Định Cư)
The settlement enters Collapse when any of the following terminal failure conditions occurs:
1. **Extinction:** Living population drops to $0$.
2. **Town Hall Destruction:** Town Hall is destroyed and not reconstructed within a 3-game-day ($72$ game-hours) emergency grace period.
3. **Prolonged Anarchy:** Settlement Stability remains at $0\%$ continuously for 3 consecutive game-days ($72$ game-hours).

When collapse triggers, the simulation stops and displays the **Collapse Summary Screen** with peak population, days survived, and primary failure causes. Save data is preserved.

---

## 8. Settlement Battle & Fortification Combat Resolution

### 8.1 Authoritative Settlement Battle Contract
Settlement battles are resolved via `BattleResolver.resolve_settlement_battle(attacker_force, defender_force, defender_world_data, seed_val) -> BattleReport`:
- **Fortification Derivation:** The defender's effective fortification level ($0 \le \text{level} \le 3$) is authoritatively derived from `defender_world_data` by counting unique grid cells containing `state == "active"` Palisades.
- **Fail-Closed Policy:** If `defender_world_data` is `null` or invalid, the resolver fails closed to fortification level 0 (+0% bonus) with `has_settlement_context = false`.
- **Authoritative Override:** Any pre-existing or omitted `fortification_level` in `defender_force` is unconditionally overwritten by the calculated level, preventing caller tampering.
- **Input Immutability:** Both `attacker_force` and `defender_force` dictionaries are deep-cloned before calculation, guaranteeing that caller resources and unit records remain unmutated regardless of battle spoils or outcome.
- **Deterministic Multiplier:** The defender's combat score receives a multiplier of $(1.0 + 0.30 \times \text{level})$ (Level 0: $1.0\times$, Level 1: $1.3\times$, Level 2: $1.6\times$, Level 3: $1.9\times$).
- **Report Enrichment:** `BattleReport.details` includes `fortification_level`, `fortification_bonus`, and `has_settlement_context`.

### 8.2 Live Settlement Defense Raid Loop
The live settlement defense loop operates deterministically via `BattleCampaignManager`:
- **Trigger & Scheduling:**
  - Declaring war via `FactionManager.declare_war()` schedules the first incoming raid exactly **3 game-days** later.
  - Subsequent raids recur every **5 game-days** while the faction remains hostile (`is_at_war == true`) and possesses positive military power (`military_power > 0.0`).
  - At most one raid per eligible faction can execute per game-day.
  - Signing peace (`propose_treaty(..., "peace")`) immediately cancels pending raids.
- **Attacking Force Conversion:**
  - `abstract_troops = clampi(roundi(military_power / 30.0), 1, 20)`
  - Equipment tier: Tier 2 for `rival_military`, Tier 1 for others.
  - Morale: `clampf(stability, 20.0, 100.0)`.
  - Terrain multiplier: Baseline $1.0\times$.
- **Defending Force Construction:**
  - Living citizens with `role == "guard"`.
  - Gated strictly by an active Barracks structure (`BuildingSystem.is_barracks_active(world_data)`). If no active Barracks exists, defending troops are $0$.
  - Citizens with temporary needs (resting, eating) remain eligible garrison members as long as they are living.
- **Zero-Troop & Casualty Bounds:**
  - Unopposed raids against undefended settlements ($0$ guards) result in an attacker victory with $0$ attacker casualties, $0$ defender casualties, and $20\%$ plunder of available resources.
  - Casualties can never exceed the initial troop count.
- **Outcome Application (Exactly-Once):**
  - **Guard Losses:** Selected deterministically (sorted by citizen ID), jobs released, health set to 0.0, and removed via `citizen_died` signal.
  - **Faction Strength:** Attacking casualties reduce `military_power` by $30.0 \times \text{casualties}$, clamped at 0.0.
  - **Plunder:** Attacker plunder deducts only available (unreserved) resources from `ResourceManager`.
  - **Idempotency:** Unique raid identifiers prevent repeat execution or duplicate mutations on save/load.

---

## 9. Player Army Recruitment, Upkeep & Garrison Defense (Package 1L)

### 9.1 Abstract Military Standing Reserve
- **Numerical Army Representation:** Recruited soldiers are tracked as an abstract numerical reserve in `PlayerArmyManager`. They are decoupled from the civilian `CitizenController` system: they do not consume housing capacity, inflate citizen population totals, or emit civilian death notifications.
- **Barracks Capacity Gating:** Each active Barracks structure provides capacity for exactly **5 soldiers** (`ARMY_CAPACITY_PER_BARRACKS = 5`).
  $$\text{Total Capacity} = \text{Active Barracks Count} \times 5$$
  Under-construction, damaged, or destroyed Barracks provide $0$ capacity. Existing soldiers are preserved if capacity drops, but further recruitment is blocked until capacity exceeds current troop strength.

### 9.2 Atomic Recruitment Transactions
- **Per-Soldier Cost:**
  - $20$ Gold (`gold`)
  - $2$ Metal (`metal`)
  - $5$ Food (`food`)
- **Transaction Safety:** Recruitment uses atomic all-or-nothing reservations (`ResourceManager.reserve_cost()` followed by `ResourceManager.commit_cost()`). If any resource is insufficient or capacity is exceeded, the transaction fails closed with zero resources deducted and zero soldier modifications.

### 9.3 Daily Food Upkeep & Supply Status
- **Upkeep Rate:** $1$ Food per soldier deducted daily on simulation day transition ticks (`00:00` Game Time).
- **Supply Gating & Failure Behavior:**
  - If available food satisfies the full daily requirement, food is committed, `is_supplied = true`, and `last_upkeep_day` updates.
  - If available food is insufficient, **no soldiers are deleted** and **no partial food is consumed**. The army transitions to unsupplied status (`is_supplied = false`), firing a notification event.
- **Recovery:** When sufficient food is available on a subsequent daily tick, the army automatically restores to supplied status upon upkeep commitment.
- **Combat Morale Scaling:**
  - Supplied Army: $70.0$ combat morale (`ARMY_MORALE_SUPPLIED`).
  - Unsupplied Army: $45.0$ combat morale (`ARMY_MORALE_UNSUPPLIED`).

### 9.4 Defending Force Composition & Casualty Absorption
- **Garrison Force Combination:** Settlement defense in `BattleCampaignManager.construct_defending_force()` combines recruited army units and active citizen Guards:
  $$\text{Total Defending Troops} = \text{Army Soldiers} + \text{Eligible Guards}$$
- **Weighted Morale Formula:**
  $$\text{Defending Morale} = \frac{(\text{Army Soldiers} \times \text{Army Morale}) + \sum \text{Guard Morale}}{\text{Total Defending Troops}}$$
- **Casualty Absorption Order:**
  1. Defender casualties are deducted first from recruited army soldiers in `PlayerArmyManager.remove_casualties()`. Abstract soldier casualties do not emit `citizen_died` signals.
  2. Any remaining overflow casualties beyond the recruited army are applied deterministically to living citizen Guards (ordered by `citizen_id`), executing their normal death lifecycle.

### 9.5 Save Validation & Upkeep Evasion Prevention
- **Clock Day Validation:** `SaveManager.validate_save_data()` enforces that `last_upkeep_day` cannot exceed the saved `game_clock.current_day`. Saves with `last_upkeep_day > clock_day` are rejected fail-closed to prevent corrupted or tampered saves from evading daily food upkeep indefinitely.
- **Fail-Closed Deserialization Clamping:** In `PlayerArmyManager.deserialize()`, if `last_upkeep_day` is greater than `TimeManager.current_day`, it is clamped to `TimeManager.current_day` to guarantee that upkeep resumes on the next scheduled simulation tick without double-charging the current day.

### 9.6 Barracks Lifecycle & Dynamic Interface Synchronization
- **Dynamic Cost Formatting:** Recruitment cost descriptions in the HUD `ArmyPanel` are built dynamically from `EconomyConfig.ARMY_RECRUIT_COST` and localized via `EconomyConfig.RESOURCE_NAMES_VI`.
- **Live State Propagation:** Barracks completion, damage, reactivation, and demolition trigger `PlayerArmyManager.notify_capacity_changed()` and update `ArmyPanel` state immediately, ensuring UI accuracy without polling while safely preserving existing soldiers.

---

## 10. Player Army Marching, Navigation & Garrison Deployment (Package 1M)

### 10.1 Movement State Machine
`PlayerArmyManager` governs army location and movement via three authoritative states:
1. `GARRISONED` ($0$): Stationed at the home settlement rally point (`current_cell == rally_cell`). The army is fully eligible for settlement defense and eligible to recruit reinforcements.
2. `MARCHING` ($1$): In transit along an active A* route on the 64×64 logical grid. The army is outside the settlement walls and not defense-eligible.
3. `IDLE_AT_FIELD` ($2$): Stationed at a field destination away from the home rally point. The army does not participate in settlement defense.

### 10.2 Rally Point & Discrete Navigation
- **Home Rally Point:** Defaulted to the plaza immediately south of the Town Hall (`Vector2i(32, 33)`). If obstructed, a deterministic outward radial search identifies the closest walkable cell.
- **A* Route Calculation:** Movement commands invoke `GridNavigation.find_path(current_cell, target_cell)` respecting terrain, water, and building occupancy.
- **Atomic Validation:** Orders to out-of-bounds cells, unwalkable cells, or the army's current cell fail closed with zero mutation to position, destination, or path.
- **Pacing & Speed Scaling:** Movement proceeds discretely at $1$ cell per $0.5$ seconds (`CELL_STEP_DURATION = 0.5s`) at $1\times$ speed, scaling proportionally with simulation speed ($2\times \to 0.25\text{s}$, $3\times \to 0.167\text{s}$) and freezing strictly when paused ($0\times$).

### 10.3 Dynamic Obstruction & Interruption Handling
- **Mid-Transit Obstruction:** If a future waypoint is blocked during transit (e.g., palisade/building constructed), `PlayerArmyManager` recalculates an alternative route to the destination. If all paths are trapped or unreachable, the army halts safely at its current cell and transitions to `IDLE_AT_FIELD`.
- **Cancellation & Return:** `cancel_move()` immediately clears the path and halts at `current_cell`. `order_return_home()` plots a direct route back to `rally_cell`.

### 10.4 Defense Eligibility & Raid Casualties
- **Garrison Gating:** Standing army soldiers only join settlement defense (`construct_defending_force`) if `is_defense_eligible() == true` (`soldier_count > 0`, `movement_state == GARRISONED`, `current_cell == rally_cell`, `current_path.is_empty()`).
- **Raid Immunity for Absent Troops:** When the army is in the field or marching, it cannot defend the settlement; settlement raids resolve without army soldiers, and absent troops take zero raid casualties.
- **Wipeout Auto-Recovery:** If casualties deplete the army to $0$, it automatically resets to `GARRISONED` at `rally_cell`.

---

## 11. Faction Strategic Intent Execution Rules (Package 1S)

### 11.1 Planner vs. Executor Separation
- **Pure Evaluation (`FactionStrategyPlanner`):** `evaluate_faction_intent(fac)` and `FactionManager.get_faction_strategic_intent(id)` / `evaluate_all_strategic_intents()` are strictly read-only and never deduct resources or mutate faction state.
- **Deterministic Execution (`FactionStrategyExecutor`):** Executed once per simulation day per active faction in `FactionManager.update_daily_simulation(day)` in sorted alphabetical key order (`neutral_tribe`, `rival_merchant`, `rival_military`).

### 11.2 Canonical Strategic Intent Action Table
| Intent ID | Strategic Goal | Preconditions | Atomic Resource Cost | Bounded State Deltas & Ceilings |
|---|---|---|---|---|
| `military_buildup` | `military_expansion` | `existence_status == "active"`, `military_power < 120.0` | `10 Metal + 25 Gold` | `military_power = min(military_power + 5.0, 120.0)` |
| `trade_expansion` | `trade_dominance` | `existence_status == "active"`, `is_at_war == false`, `gold < 1000` or `stability < 95.0` | `5 Tools` | `gold = min(gold + 30, 1000)`, `stability = min(stability + 2.0, 95.0)` |
| `community_development` | `community_growth` | `existence_status == "active"`, `population < 80` or `stability < 90.0` | Pre-ascension `neutral_tribe`: `0` (unified with `+1` daily settlement growth); direct/other: `10 Wood + 5 Herbs` | `population = min(population + 1, 80)`, `stability = min(stability + 2.0, 90.0)` |
| `power_consolidation` | `consolidate_power` | `existence_status == "active"`, `type == "emerging_power"`, not `ascended_today`, `military_power < 90.0` or `stability < 95.0` | `15 Wood + 10 Herbs` | `military_power = min(military_power + 4.0, 90.0)`, `stability = min(stability + 2.0, 95.0)` |

### 11.3 Fail-Closed & Idempotency Guarantees
- **All-or-Nothing Resource Deduction:** If any required resource is missing or below cost, the action fails closed (`REASON_INSUFFICIENT_RESOURCES`) with zero resources deducted.
- **Ceiling Protection:** When all target attributes for an intent have already reached their ceiling, the action fails closed (`REASON_AT_CAP`) without wasting faction resources.
- **Ascension-Day Non-Duplication:** On the day `neutral_tribe` ascends to `emerging_power`, ascension sets `military_power = 55.0` and `stability = 85.0`, and `power_consolidation` records `ASCENDED_THIS_TICK` without applying a second mutation on that same tick.
- **Same-Day & Save/Load Idempotency:** Per-faction `last_executed_days` and `last_tribe_growth_day` are persisted under `factions.strategy_executor` in `SaveManager`, preventing duplicate execution on same-day repeat calls or after Save/Load.

---

## 12. Deterministic Autonomous Faction Diplomacy Rules (Package 1T)

### 12.1 Pure Evaluation vs. Bounded Execution
- **Pure Evaluator (`FactionDiplomacyPlanner`):** `evaluate_diplomatic_action(fac)` is 100% side-effect-free and returns a structured decision (`faction_id`, `action_id`, `eligible`, `reason_code`, `inputs`, `explanation`) for canonical actions `declare_war`, `sign_peace`, or `none`.
- **Daily Execution Ordering (`FactionManager.update_daily_simulation(day)`):**
  1. Neutral tribe daily pre-ascension growth and ascension check (`can_emerging_faction_ascend(day)`).
  2. Autonomous diplomacy evaluation and execution (`execute_faction_diplomatic_action(fid, day)`) in sorted faction-ID order (`neutral_tribe`, `rival_merchant`, `rival_military`).
  3. Strategic intent evaluation (`FactionStrategyPlanner`) and execution (`FactionStrategyExecutor`) in sorted faction-ID order.
  - Because Step 2 executes before Step 3, any faction declaring war on Day $D$ immediately enters wartime posture on Day $D$ (and cannot complete peacetime `trade_expansion` on that tick), while any faction signing peace on Day $D$ immediately resumes peacetime posture on Day $D$.

### 12.2 Autonomous War Declaration Rules (`declare_war`)
An AI faction autonomously declares war on the player if and only if all of the following hold:
1. `existence_status == "active"` (`in_exile` and `eliminated` factions cannot initiate war).
2. `strategic_goal == "military_expansion"` **OR** (`type == "emerging_power"` and `strategic_goal == "consolidate_power"`). Pre-ascension `neutral_tribe` (`community_growth`), unascended `consolidate_power`, and `trade_dominance` factions never autonomously initiate war.
3. `is_at_war == false`.
4. `has_nap == false` and `has_alliance == false`.
5. `opinion <= -60.0` (`WAR_MAX_OPINION = -60.0`).
6. `military_power >= 65.0` (`WAR_MIN_MILITARY_POWER = 65.0`).
7. `stability >= 50.0` (`WAR_MIN_STABILITY = 50.0`).

Execution routes through `FactionManager.declare_war(faction_id)`, which sets `is_at_war = true`, `has_nap = false`, `has_alliance = false`, `disposition = HOSTILE`, reduces `opinion` by `-50.0` (clamped to `-100.0`), emits `war_declared` and `relation_changed`, triggers `BattleCampaignManager` raid scheduling (`current_day + 3`), and displays a Vietnamese HUD event banner.

### 12.3 Autonomous Peace Rules (`sign_peace`)
An AI faction at war autonomously signs peace with the player if and only if all of the following hold:
1. `is_at_war == true`.
2. `existence_status == "active"` or `existence_status == "in_exile"` (`eliminated` factions never execute diplomacy).
3. `military_power <= 20.0` (`PEACE_MAX_MILITARY_POWER = 20.0`) **OR** `stability <= 25.0` (`PEACE_MAX_STABILITY = 25.0`).

Execution routes through `FactionManager.propose_treaty(faction_id, "peace")`, which sets `is_at_war = false`, increases `opinion` by `+20.0` and recalculates `disposition`, emits `peace_signed` and `relation_changed`, cancels any pending raid in `BattleCampaignManager`, and displays a Vietnamese HUD event banner (`"Hòa Bình Lập Lại!"`).

### 12.4 Anti-Oscillation & Save/Load Persistence
- **At-Most-Once Daily Evaluation:** `FactionManager` records `_last_diplomacy_days[faction_id] = day` when evaluating an active or in-exile faction for day `day`. Any subsequent autonomous diplomacy call for that faction on the same day (or an earlier day) returns `ALREADY_EVALUATED_TODAY` with zero state changes and zero signal emissions, preventing same-day war/peace oscillation.
- **Persistence & Fail-Closed Validation:** `last_diplomacy_days` is persisted under `factions.strategy_executor.last_diplomacy_days` (`SAVE_SCHEMA_VERSION = 1`). `SaveManager.validate_save_data()` validates that `last_diplomacy_days` is a `Dictionary` with non-empty string keys and integer day values in `[1, 36500]` that do not exceed `game_clock.current_day`, rejecting corrupted or future timestamps fail-closed before world mutation.

---

## 13. Pairwise Faction Relations Rules (Package 1U)

### 13.1 Canonical Pairwise Identity & Player Isolation
- **Single Canonical Record per Unordered Pair:** Every distinct pair of NPC factions `(A, B)` in `FactionManager` (`neutral_tribe`, `rival_merchant`, `rival_military`) has exactly one `FactionRelationData` record ordered lexicographically (`faction_a < faction_b`) and keyed by `pair_key = faction_a + "__" + faction_b`. Queries and mutations with `(A, B)` and `(B, A)` resolve to the exact same record.
- **Directional Opinions & Shared Treaty/War State:** Each record stores independent directional opinions `opinion_a_to_b` and `opinion_b_to_a` (initialized to `0.0`, clamped to `[-100.0, 100.0]`) alongside shared `is_at_war`, `has_nap`, and `has_alliance` booleans.
- **Strict Separation from Player Diplomacy:** NPC-to-NPC relations never mutate `FactionData.opinion`, `FactionData.is_at_war`, `FactionData.has_nap`, or `FactionData.has_alliance`, and never emit player-facing `war_declared` / `peace_signed` signals or schedule settlement raids in `BattleCampaignManager`.
- **Ascension Identity Preservation:** When `neutral_tribe` ascends to `emerging_power` (`Liên Minh Rừng Thiêng`), its stable faction ID remains `"neutral_tribe"`, preserving all canonical pair keys and existing pairwise relationships.

### 13.2 Pairwise War, Peace, NAP & Alliance Transitions
- **`declare_war_between_factions(initiator_id, target_id)`:** Requires two distinct known factions with `existence_status == "active"` and `is_at_war == false`. Sets `is_at_war = true`, clears `has_nap = false` and `has_alliance = false`, applies `-50.0` opinion delta in both directions, and emits `faction_pair_war_declared` and `faction_pair_opinion_changed`.
- **`sign_peace_between_factions(id_1, id_2)`:** Requires two distinct known factions with `existence_status` in `["active", "in_exile"]` (`eliminated` blocked) and `is_at_war == true`. Sets `is_at_war = false`, applies `+20.0` opinion delta in both directions, and emits `faction_pair_peace_signed` and `faction_pair_opinion_changed`.
- **`sign_nap_between_factions(id_1, id_2)`:** Requires two distinct `active` factions with `is_at_war == false`, `has_nap == false`, and mutual opinions `opinion_a_to_b >= 0.0` and `opinion_b_to_a >= 0.0`. Sets `has_nap = true`, applies `+15.0` opinion delta in both directions, and emits `faction_pair_treaty_signed(..., "nap", ...)` and `faction_pair_opinion_changed`.
- **`sign_alliance_between_factions(id_1, id_2)`:** Requires two distinct `active` factions with `is_at_war == false`, `has_alliance == false`, and mutual opinions `opinion_a_to_b >= 60.0` and `opinion_b_to_a >= 60.0`. Sets `has_alliance = true` and `has_nap = true`, applies `+25.0` opinion delta in both directions, and emits `faction_pair_treaty_signed(..., "alliance", ...)` and `faction_pair_opinion_changed`.

### 13.3 Save/Load Persistence & Fail-Closed Validation
- **Persistence Location:** Serialized under `data["factions"]["pairwise_relations"]` (`SAVE_SCHEMA_VERSION = 1`).
- **Fail-Closed Validation:** `SaveManager.validate_save_data()` rejects non-Dictionary `pairwise_relations`, self-relations, unknown faction IDs, non-canonical ordering (`faction_a > faction_b`), key/field mismatches, duplicate pairs, non-finite or out-of-range opinions (`< -100.0` or `> 100.0`), non-boolean flags, and contradictory states (`is_at_war && (has_nap || has_alliance)` or `has_alliance && !has_nap`) before world mutation. Legacy saves omitting `pairwise_relations` initialize clean neutral defaults.

---

## 14. Autonomous Inter-Faction Warfare & Conflict Simulation (Package 2E)

### 14.1 Daily Simulation Ordering
- Daily pairwise diplomacy is evaluated in Step 2b of `FactionManager.update_daily_simulation(day)` (`execute_all_pairwise_diplomacy`) immediately after player-facing autonomous diplomacy and before daily strategic economic intent execution (Step 3).
- At-most-once evaluation per day per canonical pair is enforced via `_last_pairwise_diplomacy_days[pair_key] = day`.

### 14.2 Autonomous War Declaration Prerequisites
An NPC faction autonomously initiates war against another NPC faction if and only if all of the following hold:
1. Both factions are in `active` existence status (`in_exile` and `eliminated` factions cannot wage war).
2. The pair is not currently at war (`is_at_war == false`).
3. Neither faction is under an active truce (`is_on_truce(current_day) == false`).
4. Neither faction has an active NAP (`has_nap == false`) or Alliance (`has_alliance == false`).
5. Initiator opinion of the target is at or below the war threshold:
   $$\text{opinion}(\text{initiator} \to \text{target}) \le -50.0 \quad (\text{INTER\_WAR\_MAX\_OPINION})$$
6. Initiator military strength is at or above the minimum readiness threshold:
   $$\text{military\_power} \ge 40.0 \quad (\text{INTER\_WAR\_MIN\_MILITARY\_POWER})$$
7. Initiator internal stability is at or above the minimum cohesion threshold:
   $$\text{stability} \ge 30.0 \quad (\text{INTER\_WAR\_MIN\_STABILITY})$$
8. Relative military power ratio satisfies the strategic safety margin:
   $$\frac{\text{initiator.military\_power}}{\text{target.military\_power}} \ge 0.65 \quad (\text{INTER\_WAR\_MIN\_POWER\_RATIO})$$
9. Initiator strategic goal justifies conflict:
   - `military_expansion`
   - Ascended `emerging_power` with `consolidate_power`
   - Extreme historical enmity ($\text{opinion} \le -75.0$)
   - Target is `rival_merchant` (trade route competition)

### 14.3 Campaign Preparation, Resolution & Outpost Siege
- **Campaign Scheduling:** War declaration automatically schedules a military campaign in `BattleCampaignManager` with a 2-day preparation delay (`INTER_FACTION_CAMPAIGN_PREP_DAYS = 2`). Subsequent campaigns between warring factions are spaced at 4-day intervals (`INTER_FACTION_SUBSEQUENT_INTERVAL_DAYS = 4`).
- **Real Combat Resolution:** Resolved via authoritative `BattleResolver.resolve_battle` with troops proportional to `military_power / 20.0` (clamped between 3 and 10 troops).
- **Casualties & Resource Plunder:**
  - Combat casualties deduct proportionally from `military_power` and `population`.
  - Plundered resources are strictly transferred from the defender's `resources` stockpile to the attacker's stockpile without fabricating phantom resources.
- **Outpost Damage & Sacking:**
  - Attacker victory inflicts real siege damage to the defender's regional outpost tracked by `FieldSiegeManager` ($15.0\text{ HP}$ per surviving attacker troop).
  - Outpost health reaching $0.0\text{ HP}$ transitions the outpost to sacked/captured status (`is_captured = true`).

### 14.4 War Weariness & Peace Negotiation
- **Weariness Trigger:** An active inter-faction war evaluates mutual peace when:
  1. War duration $\ge 12$ game days (`INTER_WAR_WEARINESS_DAYS = 12`) **OR**
  2. Either faction suffers military exhaustion:
     $$\text{military\_power} \le 20.0 \quad \text{OR} \quad \text{stability} \le 25.0$$
- **Truce Cooldown & Anti-Oscillation:**
  - Signing peace terminates war (`is_at_war = false`), grants $+20.0$ mutual opinion (pulling relations up to $-30.0$, far above the $-50.0$ threshold), establishes a 6-day truce (`INTER_TRUCE_DURATION_DAYS = 6`), and cancels any pending inter-faction campaigns.
  - During the truce (`current_day < truce_until_day`), all declaration attempts fail closed with `PAIR_REASON_ERR_ON_TRUCE`.

### 14.5 Player Economic Impact & Trade Caravan Wartime Surcharge
- **Wartime Surcharge:** When a trade caravan arrives from an origin faction currently engaged in war, all commodity sell prices to the player incur a $+15\%$ risk surcharge (`WARTIME_PRICE_SURCHARGE = 0.15`), with a guaranteed minimum markup of at least $+1$ Gold per commodity unit.
- **Authoritative Transparency:** The visiting caravan inspector and Trade HUD display a prominent wartime warning: `⚠️ VÙNG CHIẾN SỰ: Xuất phát từ lãnh thổ có chiến tranh (Phụ phí rủi ro: +15% giá mua)`.

### 14.6 Player Isolation & Diplomacy HUD Integration
- **Strict Player Isolation:** Inter-faction wars never alter player opinions, player treaties, or player-targeted raids.
- **World Warfare Transparency:**
  - Real-time HUD event banners notify the player of world war declarations, peace treaties, campaign mobilization, and battle results with casualty reports.
  - Section 3 of the Diplomacy Panel ("⚔️ QUAN HỆ & CHIẾN SỰ GIỮA CÁC THẾ LỰC (NPC — NPC)") displays all 3 canonical pairs with color-coded status badges, 2-way opinion readouts, Casus Belli, war duration, pending campaign info, recent battle summaries, and player alliance warnings.

---

## 15. Outpost Capture & Territorial Control Rules (Package 2G)

### 15.1 Authoritative Outpost Ownership Model
Each regional outpost (`SiegeObjectiveActor`) tracked by `FieldSiegeManager` maintains persistent ownership metadata:
1. `owning_faction_id`: Current authoritative controlling faction (`"player"`, `"rival_military"`, `"rival_merchant"`, `"neutral_tribe"`).
2. `original_owner_id`: Founding faction identifier, set upon initial objective registration and immutable across captures.
3. `previous_owner_id`: Controlling faction immediately preceding the most recent conquest transaction.
4. `capture_revision`: Monotonically increasing non-negative integer tracking the total number of ownership transfers.
5. `last_capture_tx_id`: Unique non-empty transaction identifier (`"player_siege_<id>"` or `"npc_campaign_<id>"`), guaranteeing idempotent execution. Whitespace-only or empty transaction IDs are strictly rejected fail-closed with zero state changes.
6. `is_valid_owner_id`: When `FactionManager` exists, only `"player"` or recognized existing factions are accepted. If `FactionManager` is null, non-player owner assignment fails closed.

### 15.2 Post-Conquest State & Health Recovery Contract
- **Never Permanently Destroyed:** Outposts are permanent territorial anchor points. When reduced to $0.0\text{ HP}$ or captured via siege, they are never deleted from the world map or freed from memory.
- **Health Restoration Formula:** Upon successful capture, the outpost's health is atomically restored to exactly $35\%$ of its maximum health:
  $$\text{health} = \text{round}(\text{max\_health} \times 0.35)$$
- **State Normalization:** Capture resets `is_alive = true`, `is_captured = true`, `is_under_active_siege = false`, and clears remaining defender units (`defenders.clear()`).
- **Recapture Capability:** Living outposts (`is_alive == true`) can receive damage and be sieged repeatedly regardless of `is_captured == true`.

### 15.3 Visual Territorial Presentation & Banner Heraldry
Outpost banners dynamically display the heraldic colors and conquest markers of their current controller:
- **Player Banner:** Royal Blue (`Color(0.2, 0.45, 0.95, 0.95)`), golden banner pole (`Color(0.85, 0.7, 0.2)`), golden conquest finial crest (`Color(1.0, 0.85, 0.2)`), and dynamic building label `"Tiền Đồn Vương Quốc"`.
- **Rival Military Banner:** Crimson Red (`Color(0.85, 0.2, 0.2, 0.95)`), dark iron pole (`Color(0.1, 0.1, 0.1)`), and label `"Tiền Đồn Rival_military"` (hoặc `"Tiền Đồn Cổ Thành Thiết Giáp"`).
- **Rival Merchant Banner:** Amber Gold (`Color(0.92, 0.72, 0.15, 0.95)`), dark iron pole (`Color(0.1, 0.1, 0.1)`), and label `"Tiền Đồn Rival_merchant"` (hoặc `"Tiền Đồn Thương Hội Vân Đồn"`).
- **Neutral Tribe Banner:** Forest Green (`Color(0.2, 0.75, 0.35, 0.95)`), dark iron pole (`Color(0.1, 0.1, 0.1)`), and label `"Tiền Đồn Neutral_tribe"` (hoặc `"Tiền Đồn Bản Làng Rừng Xanh"`).
- **Health Bar Color Coding:**
  - Player-controlled outposts render a vibrant green health bar (`Color(0.2, 0.8, 0.2)`).
  - Hostile/NPC-controlled outposts render a standard crimson health bar (`Color(0.8, 0.2, 0.2)`).

### 15.4 Tactical Field Siege Integration & Friendly Siege Prevention
- **Player Conquest Flow:** When a player army conducts a successful field siege resolving to `VICTORY`, `FieldSiegeManager._resolve_siege_outcome()` triggers `transfer_ownership("player", "player_siege_" + siege_id)`.
- **Friendly Siege Prevention:** `FieldSiegeManager.can_launch_field_siege()` strictly rejects launching sieges against player-controlled outposts (`owning_faction_id == "player"`).
- **Recapture Allowance:** The player is freely permitted to siege hostile NPC outposts that were previously player-owned or recaptured.

### 15.5 NPC Autonomous Warfare Outpost Sacking & Conflict Resolution
- **Dynamic Defender Objective Targeting:** `BattleCampaignManager.schedule_inter_faction_campaign()` and `resolve_inter_faction_campaign()` dynamically resolve target outposts belonging to the defending faction.
- **Outpost Sacking:** Attacker victory inflicts real siege damage ($15.0\text{ HP}$ per surviving troop). If outpost health drops to $0.0\text{ HP}$, the outpost is sacked and authoritatively transferred to the attacking faction with `tx_id = "npc_campaign_" + campaign_id`.
- **Active Player Siege Collision Protection:** If an outpost is currently under active player siege (`is_under_active_siege == true`), NPC inter-faction campaigns strictly skip dealing damage or transferring ownership to prevent desynchronization.

### 15.6 Fail-Closed Save/Load Schema & Migration
- **Schema Validation:** `SaveManager.validate_save_data()` strictly validates the types and values of `original_owner_id` (String), `previous_owner_id` (String), `capture_revision` (non-negative int), and `last_capture_tx_id` (String).
- **100% Backward-Compatible Migration:** Legacy saves without Package 2G metadata automatically default to `original_owner_id = owning_faction_id`, `previous_owner_id = ""`, `capture_revision = 0`, and `last_capture_tx_id = ""`.

### 15.7 Garrison Ownership Lifecycle & Recapture Filtering
- **Centralized Garrison Release:** Upon any successful, validated, non-duplicate outpost ownership transfer (`transfer_outpost_ownership`), the previous owner's garrison defenders are authoritatively unassigned:
  - `is_garrison_defender` is set to `false`.
  - `assigned_objective_id` is cleared (`""`).
  - Combat and pursuit states are safely returned to idle (`clear_combat_and_pursuit_to_idle`).
  - Units are transitioned into `RECOVER_RETREAT` state (state 5) to retreat toward the map border and despawn via the standard `EnemyMilitaryManager` lifecycle.
  - The soldiers' original `owning_faction_id` is strictly preserved (never converted to the capturing faction).
  - Surviving defenders are never deleted instantly, maintaining immersion and simulation consistency.
- **Fail-Closed Garrison Protection:** Invalid transactions, non-existent owners, duplicate transaction IDs, and same-owner transfers strictly do not trigger garrison release or retreat state transitions.
- **Defensive Faction Ownership Filtering during Siege Launch:** `FieldSiegeManager.launch_field_siege()` strictly filters candidate defenders from `defending_unit_ids`, `get_garrison_defenders_by_objective()`, and proximity reuse using `is_eligible_garrison_defender()`. A defender is only accepted if it belongs to `target_faction_id`, is alive, is not in `RECOVER_RETREAT`, and is not assigned to a different outpost. Soldiers of a former owner are never reused to defend an outpost for the current owner.
