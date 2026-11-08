# PACKAGE 3B — DYNAMIC TRADE ROUTE INTERCEPTION & CARAVAN DEFENSE
**Authoritative Scope & Technical Implementation Specification**  
**Game Design Document Reference:** `docs/GDD.md` §11.1, §11.2 (Caravans, Trade Routes, Escort Operations & Bandit Ambush)  
**Milestone Reference:** Milestone 3 — Strategic Gameplay Complete  
**Target Branch:** `feature/package-3b-caravan-defense`  
**Base Commit:** (Head of `feature/package-3a-outpost-garrison-reinforcement`)  

---

## 1. OBJECTIVE & STRATEGIC GAMEPLAY GAP

### Current Gameplay Limitations:
1. **Abstract Caravan Transit:** In Package 1T/1U, merchant caravans arrive at the settlement plaza abstractly on scheduled days, docking and trading before vanishing.
2. **Unguarded Trade Arteries:** While outposts are now secured by garrisons (Package 3A), trade routes between allied settlements and the player's colony lack dynamic escort, making traders vulnerable to wilderness bandit raids.
3. **Escort & Interception Mechanics:** GDD §11.1 and §11.2 require that players can deploy squads to escort vital supply caravans, intercept rival smugglers, or rescue ambushed allied traders to gain diplomatic favor and lucrative trade goods.

### Package 3B Core Deliverables:
- **Physical Caravan Map Transit:** Trade caravans travel across the isometric map along navigable roads or terrain routes between regional edge portals and the colony trade post.
- **Bandit Ambush Events:** Hostile bandit squads can ambush moving caravans along high-risk border routes.
- **Escort Dispatch Orders:** The player can assign tactical units or garrison squads to escort trade caravans, automatically engaging ambushers.
- **Plunder & Rescue Rewards:** Successfully defending an ambushed caravan awards bonus trade stock and major diplomatic relation boosts with the merchant faction.
- **Save/Load Persistence:** Full state persistence for in-transit caravans, escort assignments, and ambush encounters.

---

## 2. PRE-REQUISITES & DEPENDENCY CHECK
- Milestone 2 Complete:
  - Package 2K (Manual Citizen Commands) ✅
  - Package 2L (Settlement Citizen Roster Panel) ✅
  - Package 2M (Civic Building Damage & Maintenance Repair) ✅
- Milestone 3 Progress:
  - Package 3A (Territorial Outpost Garrisoning & Reinforcement) ✅
- All 65 regression test suites passing with 0 baseline failures and 0 unexpected failures.

---

## 3. PENDING AUTHORIZATION
*Implementation will commence upon formal review and authorization by the project owner.*
