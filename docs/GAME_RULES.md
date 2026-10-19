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
