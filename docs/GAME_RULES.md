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
- **Storage Conservation Rule:** Items in local workplace buffers do not count toward central construction availability until physically transported by Haulers to a Storehouse or Town Hall.
- **Atomic Reservation:** `ResourceManager.reserve_resource(id, amount) -> bool` guarantees materials cannot be double-spent across competing build or crafting orders.

---

## 4. Buildings & Footprints

### 4.1 Initial Settlement Structures
| Building | Footprint (Grid) | Footprint (Local Diamond) | Starting Count | Function & Capacity |
|---|---|---|---|---|
| **Town Hall** | $3 \times 3$ cells | $96 \times 48$ px base | 1 | Settlement hub, $500$ storage, immigration focal point |
| **House** | $2 \times 2$ cells | $64 \times 32$ px base | 4 | $6$ citizens housing cap each ($24$ total starting cap) |
| **Farm** | $2 \times 2$ cells | $64 \times 32$ px base | 1 | Base output $5.0$ Food/farmer/day, max 5 workers |
| **Woodcutter Camp** | $2 \times 2$ cells | $64 \times 32$ px base | 1 | Base output $5.0$ Wood/worker/day, max 4 workers |
| **Storehouse** | $2 \times 2$ cells | $64 \times 32$ px base | 1 | $1000$ item general resource storage |

### 4.2 Building Costs & Construction States
- **Construction States:** `Unbuilt` $\to$ `Placing` $\to$ `UnderConstruction` $\to$ `Active` $\to$ `Paused` $\to$ `Damaged` $\to$ `Destroyed`.
- **Occupancy Rule:** A building footprint of size $W \times H$ occupies cells $(gx + i, gy + j)$ for $0 \le i < W$ and $0 \le j < H$. All footprint cells must be buildable, walkable terrain, and unreserved.

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
