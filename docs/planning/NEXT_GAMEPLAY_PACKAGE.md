# PACKAGE 3B — CAMPAIGN FOG OF WAR & SCOUT RECONNAISSANCE
**Authoritative Scope & Technical Implementation Specification**  
**Game Design Document Reference:** `docs/GDD.md` §3.4, §8.2, §10.4  
**Milestone Reference:** Milestone 3 — Strategic Gameplay Complete  
**Target Branch:** `feature/package-3b-fog-of-war-reconnaissance`  
**Base Commit:** (Head of `feature/package-3a-outpost-garrison-reinforcement`)  

---

## 1. OBJECTIVE & STRATEGIC GAMEPLAY GAP

### Current Gameplay Limitations:
1. **Isolated Outpost Vision:** Captured territorial outposts (`SiegeObjectiveActor`, Package 2G / 3A) project territorial influence via `TerritoryManager`, but do not project vision in `WorldView.refresh_world_vision()`, leaving secured frontiers in pitch-black fog.
2. **Combat Reconnaissance Disconnect:** GDD §10.4 explicitly mandates that battle resolution depends on "Trinh sát" (Reconnaissance). Currently, offensive campaigns against objectives in unexplored fog execute with identical effectiveness as fully observed targets.
3. **Exploration Roles:** While civilian workers have an Explore command (Package 2K), strategic reconnaissance for military campaigns is not yet connected to the `BattleResolver`.

### Package 3B Core Deliverables:
- **Outpost Vision Projection:** Integrate player-owned, living territorial outposts as vision observers in `WorldView.refresh_world_vision()` with an approved radius (radius 6 proposed per DEC-3B-01), illuminating borderlands.
- **Combat Reconnaissance Factor:** Integrate reconnaissance into `BattleResolver.resolve_battle()`: 1.00 for scouted/explored targets, with a proposed provisional blind attack penalty (0.85 combat score multiplier proposed per DEC-3B-02) when attacking objectives in `UNEXPLORED` fog.
- **Reconnaissance Battle Feedback:** Update `BattleReport` and HUD battle outcome notifications to explain reconnaissance impacts clearly per GDD §10.4.
- **Zero Redundant Visibility Grids:** 100% reuse of the existing 3-state `FogOfWar` system (`scripts/world/fog_of_war.gd`).
- **Save/Load Compatibility:** 100% preservation of existing `SaveManager` serialization for explored coordinates.

---

## 2. PRE-REQUISITES & DEPENDENCY CHECK
- **Milestone 2 Complete:**
  - Package 2K (Manual Citizen Commands) ✅
  - Package 2L (Settlement Citizen Roster Panel) ✅
  - Package 2M (Civic Building Damage & Maintenance Repair) ✅
- **Milestone 3 Progress:**
  - Package 3A (Territorial Outpost Garrisoning & Reinforcement) ✅
  - Cross-package repair reservation persistence hardened ✅
  - Global soldier identity conservation verified ✅
- **Regression Suite Baseline:**
  - 65/65 suites passing with Exit Code 0, 0 baseline failures, 0 unexpected failures.

---

## 3. PENDING OWNER DECISION APPROVAL & IMPLEMENTATION AUTHORIZATION

Package 3B architecture is provisionally drafted with 4 mandatory implementation gates awaiting formal project owner approval. Existing gameplay baselines (DEC-01 through DEC-07, covering outpost capacity defaults, fortification limits, defender multipliers, building damage thresholds, and repair economy) remain documented baselines that do not block Package 3B.

### Mandatory Package 3B Implementation Gates:
1. **DEC-3B-01: Outpost Vision Radius**
   - *Proposed Default:* Radius `6` (matches `TerritoryManager.OUTPOST_RADIUS`).
   - *Alternative Options:* Radius `5` (conservative) or `8` (matches Town Hall).
   - *Status:* Pending Owner Approval.
2. **DEC-3B-02: Reconnaissance Combat Effect**
   - *Proposed Default:* Attacker penalty $\times 0.85$ (15% reduction) if target is in `UNEXPLORED` fog; $\times 1.00$ if scouted.
   - *Alternative Options:* Additive penalty (e.g. $-10$ combat score) or Defender bonus ($\times 1.15$ if defender has active vision).
   - *Provisional Note:* GDD §10.4 requires "Trinh sát" qualitatively; `0.85` is strictly a proposed default, not an approved rule.
   - *Status:* Pending Owner Approval.
3. **DEC-3B-03: Scouting Dispatch Model**
   - *Proposed Default:* Passive/Abstract discovery where target cell uncovered by civilian Explore (Package 2K) or army movement satisfies reconnaissance.
   - *Alternative Options:* Active dispatch of dedicated Scout missions from Barracks with travel time and resource costs.
   - *Status:* Pending Owner Approval.
4. **DEC-3B-04: Formal Owner Implementation Authorization**
   - *Requirement:* Explicit written sign-off from project owner to begin Package 3B production code changes.
   - *Status:* Pending Owner Approval.

*No production gameplay code changes will be made until DEC-3B-01 through DEC-3B-04 are formally approved.*
