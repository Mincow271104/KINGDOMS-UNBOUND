# PACKAGE 3A — TERRITORIAL OUTPOST GARRISONING & REINFORCEMENT
**Authoritative Scope & Technical Implementation Specification**  
**Game Design Document Reference:** `docs/GDD.md` §6.3, §10.5 (Territorial Outposts, Garrisoning & Strategic Frontier Defense)  
**Milestone Reference:** Milestone 3 — Strategic Gameplay Complete  
**Target Branch:** `feature/package-3a-outpost-garrison`  
**Base Commit:** (Head of `feature/package-2m-building-damage-repair`)  

---

## 1. OBJECTIVE & STRATEGIC GAMEPLAY GAP

### Current Gameplay Limitations:
1. **Passive Outpost Capture:** In Package 2G, territorial outposts (Watchtower, Palisade, Frontier Forts) project territorial influence and expand vision, but once captured, they remain ungarrisoned or purely abstract markers without stationed soldiers.
2. **Vulnerability to NPC Reconquest:** Hostile factions and bandit warbands can walk into outpost radii without encountering tactical defensive resistance.
3. **Missing Troop Deployment Loop:** GDD §10.5 specifies that players can dispatch squads from their central settlement army to garrison remote outposts, reducing travel time to distant conflicts and locking down border regions.

### Package 3A Core Deliverables:
- Implement formal outpost garrisoning: players can station up to $N$ soldiers at captured outposts via right-click dispatch or HUD Outpost Inspection.
- Localized garrison defense: garrisoned troops automatically engage hostile trespassers within the outpost's tactical radius.
- Outpost supply lines & upkeep: stationed troops consume food from settlement supply convoys or daily upkeep deductions.
- Save/load persistence for garrison allocations and defensive stances.

---

## 2. PRE-REQUISITES & DEPENDENCY CHECK
- Milestone 2 Complete:
  - Package 2K (Manual Citizen Commands) ✅
  - Package 2L (Settlement Citizen Roster Panel) ✅
  - Package 2M (Civic Building Damage & Maintenance Repair) ✅
- All 64 regression test suites passing with 0 baseline failures and 0 unexpected failures.

---

## 3. PENDING AUTHORIZATION
*Implementation will commence upon formal review and authorization by the project owner.*
