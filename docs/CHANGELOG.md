# KINGDOMS UNBOUND — User-Visible Changelog

All notable changes to the Kingdoms Unbound project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### [Package 2G] - 2026-11-01
#### Added
- Outpost Capture & Territorial Control (`SiegeObjectiveActor`, `FieldSiegeManager`, `BattleCampaignManager`, `WorldView`, `SaveManager`):
  - Authoritative outpost ownership model tracking dynamic `owning_faction_id`, immutable founding `original_owner_id`, historical `previous_owner_id`, monotonic `capture_revision`, and transaction idempotency token `last_capture_tx_id`.
  - Atomic, idempotent ownership transfer via `SiegeObjectiveActor.transfer_ownership(new_owner_id, tx_id)` and authoritative coordinator `FieldSiegeManager.transfer_outpost_ownership(obj_id, new_owner_id, tx_id)`.
  - Strict transaction and owner validation: Rejects empty or whitespace-only transaction IDs; validates owner IDs against `"player"` or registered factions via `FactionManager`, failing closed for non-player owners when `FactionManager` is unavailable.
  - Strict query invariance: Removed fixture reset logic from `can_launch_field_siege()`, preserving pure read-only check semantics and delegating state resets cleanly to test fixtures (`test_field_siege.gd` Case D5).
  - Post-conquest recovery contract: Outposts are never permanently deleted from the world map. Upon capture, health is restored to exactly 35% of `max_health` (`round(max_health * 0.35)`), resetting `is_alive = true`, `is_captured = true`, and clearing active siege state.
  - Distinct visual territorial recognition with faction heraldry colors: Royal Blue (`Color(0.2, 0.45, 0.95, 0.95)`) with golden pole (`Color(0.85, 0.7, 0.2)`) and conquest finial for `"player"`, Crimson Red (`Color(0.85, 0.2, 0.2, 0.95)`) for `rival_military`, Amber Gold (`Color(0.92, 0.72, 0.15, 0.95)`) for `rival_merchant`, and Forest Green (`Color(0.2, 0.75, 0.35, 0.95)`) for `neutral_tribe`.
  - Dynamic health bar color: Player-owned outposts render green health bars (`Color(0.2, 0.8, 0.2)`), while hostile/NPC outposts render red health bars (`Color(0.8, 0.2, 0.2)`).
  - Real-time HUD conquest event banners: `"ĐÃ CHIẾM TIỀN ĐỒN!"` for player field siege conquest and `"BIẾN ĐỘNG LÃNH THỔ!"` for NPC autonomous warfare territorial conquests.
  - Tactical field siege integration: Resolving a field siege as `VICTORY` authoritatively transfers the outpost to `"player"`, resets defenders, and prevents friendly sieges against player-owned outposts.
  - Inter-faction warfare campaign integration: Attacking NPC victories dynamically resolve the defender's outpost, inflict siege damage, sack the outpost on breach, and transfer territorial ownership with unique campaign transaction IDs.
  - Collision avoidance: Campaigns strictly skip damaging or capturing outposts currently under active player siege (`is_under_active_siege == true`).
  - End-to-end `SaveManager` persistence & migration: Verified via live `WorldView` scene using `serialize_world_state()` and `apply_loaded_state_to_world()`. Deserializes legacy saves safely by defaulting `original_owner_id = owning_faction_id`, `previous_owner_id = ""`, `capture_revision = 0`, and `last_capture_tx_id = ""`.
  - Automated test suite `scripts/test/test_outpost_territorial_control.gd` covering 8 mandatory test groups and 157 assertions (100% pass rate, Exit Code 0).

### [Package 2B] - 2026-10-31
#### Added
- Citizen Skill Progression & Vocational Specialization (`CitizenSkillData`, `CitizenController`, `HUD`, `SaveManager`):
  - Vocational skill progression model (`scripts/entities/citizen_skill_data.gd`) tracking individual citizen proficiency across 6 core vocations: `farming`, `woodcutting`, `mining`, `smithing`, `building`, and `hauling`.
  - Canonical cumulative XP thresholds and strictly bounded multipliers per GDD §6.5:
    - Level 1 (Tập sự / Novice): 0 XP -> 1.00x efficiency (Baseline).
    - Level 2 (Học việc / Apprentice): 100 XP -> 1.08x efficiency (+8%).
    - Level 3 (Thợ lành nghề / Journeyman): 300 XP -> 1.16x efficiency (+16%).
    - Level 4 (Chuyên gia / Expert): 600 XP -> 1.25x efficiency (+25%).
    - Level 5 (Bậc thầy / Master): 1000 XP -> 1.35x efficiency (+35% approved maximum cap).
  - Real-work-only XP attribution:
    - Production: +10 XP awarded to the specific crafting worker upon committing output to workplace buffer (`produced_qty > 0`).
    - Building: +5 XP per game-hour of active construction labor contributed, preserving fractional progress.
    - Hauling: +10 XP awarded upon genuine cargo delivery and deposit into storage (`delivered_amount > 0`).
    - Zero passive XP for idle, sleeping, eating, wandering, or failed/blocked actions.
  - Measurable gameplay consequences:
    - Production jobs complete faster according to worker skill multiplier without violating recipe input-output conservation.
    - Construction sites progress additively with independent builder multipliers without compounding.
    - Haulers move faster across the grid based on hauling proficiency (48.0 px/s -> 64.8 px/s at Master Level 5).
  - Cross-training and persistence:
    - Role switching preserves 100% of earned XP across all vocations without decay or penalty.
    - SaveManager serializes `skills` dictionary per citizen, fail-closed bounds checking, with full backward compatibility for legacy saves lacking skill data.
  - Citizen Inspector UI:
    - Enhanced `CitizenInspectPanel` in `scenes/ui/hud.tscn` and `scripts/ui/hud.gd` displaying vocational title, level badge, visual XP progress bar, efficiency bonus percentage, and Level 5 maximum indicator.
  - Automated test suite `scripts/test/test_citizen_skills.gd` covering TC-SKL-01 through TC-SKL-22 (22/22 passed, Exit Code 0).

### [Package 2A] - 2026-10-31
#### Added
- Market Infrastructure & Physical Caravan Integration (`EconomyConfig`, `BuildingSystem`, `WorldView`, `CaravanMarker`, `HUD`, `SaveManager`):
  - Added Market (`market`) building blueprint to `EconomyConfig.BLUEPRINTS`: 3x3 footprint, cost 25 Wood + 10 Stone, 12.0h build time, 100 HP, 0 housing, 0 workers, 0 storage bonus, and 4 construction worker slots derived from footprint.
  - Authentic pixel art asset `assets/buildings/bld_market.png` conforming to `docs/ASSET_STYLE_GUIDE.md` 27-color palette with 3x3 diamond base (96x80 canvas) and isometric sprite offset `(-48, -56)`.
  - Static discovery helpers in `BuildingSystem`: `is_market_active()`, `get_all_active_markets()` (deterministic sorting by coordinate $y \times 64 + x$ then ID), `get_active_market()`, `get_town_hall()`, and `find_caravan_docking_cell(world_data)`.
  - Added `grid_to_world()` alias in `scripts/utils/iso_math.gd`.
  - Physical Merchant Caravan docking presentation:
    - Dedicated lightweight `CaravanMarker` actor (`scripts/trade/caravan_marker.gd`) with Y-sorting, citizen texture with saffron modulation (`Color(1.2, 1.05, 0.4, 1.0)`), ground-contact foot pivot `(-12, -30)`, and `NameLabel`.
    - Dynamic docking positioning: visiting merchant caravans dock at an unoccupied, non-water perimeter cell adjacent to the active Market.
    - Graceful Town Hall fallback: when no Market exists, or Market is under construction, or perimeter is blocked, caravans safely dock at the Town Hall perimeter without breaking trade.
    - Idempotent lifecycle management in `WorldView`: marker creation, repositioning, and removal hooked into caravan arrival, departure, building completion, cancellation, demolition, and world generation.
  - UI & HUD Integration:
    - Added `MarketBtn` ("⚖️ Chợ (25 Gỗ, 10 Đá)") to `BuildMenuPanel` grid in `scenes/ui/hud.tscn` and wired placement logic in `scripts/ui/hud.gd`.
    - Dynamic trade location indicator in `DiplomacyPanel` caravan status label (`📍 Địa điểm giao thương: Chợ` vs `📍 Địa điểm giao thương: Tòa thị chính`).
  - Persistence & Backward Compatibility:
    - Wired `refresh_caravan_marker()` into Step 20 of `SaveManager.apply_loaded_state_to_world()`.
    - Docking presentation is transient and re-derived from world state on load; zero schema changes, zero disk footprint, full backward compatibility with legacy saves.
  - Dedicated automated test suite `scripts/test/test_market.gd` covering TC-MKT-01 through TC-MKT-15 (15/15 tests passed, Exit Code 0).
#### Changed / Hardened
- Updated `scripts/test/test_palisade.gd` button count assertion from 11 to 12 building buttons in `BuildMenuPanel` grid.

### [Package 1U] - 2026-10-24
#### Added
- Pairwise Faction Relations Foundation (`FactionRelationData`, `FactionManager`, `SaveManager`):
  - Canonical pairwise relationship model `scripts/factions/faction_relation_data.gd` (`FactionRelationData`) representing each unordered NPC faction pair `(faction_a < faction_b)` with canonical `pair_key = faction_a + "__" + faction_b`, directional opinions (`opinion_a_to_b`, `opinion_b_to_a` clamped to `[-100.0, 100.0]`), and shared war/treaty state (`is_at_war`, `has_nap`, `has_alliance`).
  - Authoritative query and mutation APIs in `FactionManager`:
    - Query helpers: `get_faction_pair_key(id_1, id_2)`, `get_faction_relation_record(id_1, id_2)`, `get_faction_relation(from_id, to_id)`, `get_directed_faction_opinion(from_id, to_id)`, `are_factions_at_war(id_1, id_2)`, `do_factions_have_nap(id_1, id_2)`, `do_factions_have_alliance(id_1, id_2)`, `get_all_faction_relations()`.
    - Validated atomic mutation APIs: `set_faction_pair_opinion`, `modify_faction_pair_opinion`, `declare_war_between_factions`, `sign_peace_between_factions`, `sign_nap_between_factions`, `sign_alliance_between_factions`, `propose_treaty_between_factions`, and pair-specific signals (`faction_pair_opinion_changed`, `faction_pair_war_declared`, `faction_pair_peace_signed`, `faction_pair_treaty_signed`) strictly isolated from player-facing `FactionData` fields and settlement raids.
  - Save/Load persistence and fail-closed validation in `SaveManager`:
    - Serializes and restores `factions.pairwise_relations` (`SAVE_SCHEMA_VERSION = 1`) with full legacy save compatibility and fail-closed rejection of self-relations, unknown faction IDs, non-canonical pair ordering, mismatched keys, out-of-range/non-finite opinions, non-boolean flags, and contradictory war/treaty states.
  - Dedicated automated test suite `scripts/test/test_faction_relation_matrix.gd` covering TC-FREL.1 through TC-FREL.16 (16/16 tests passed, 151 checks passed, Exit Code 0).

### [Package 1T] - 2026-10-24
#### Added
- Deterministic Autonomous Faction Diplomacy (`FactionDiplomacyPlanner`, `FactionManager`, `SaveManager`, `HUD`):
  - Pure, side-effect-free diplomacy planner `scripts/factions/faction_diplomacy_planner.gd` (`FactionDiplomacyPlanner`) evaluating `FactionData` into structured decisions (`faction_id`, `action_id`, `eligible`, `reason_code`, `inputs`, `explanation`) for canonical actions `declare_war`, `sign_peace`, and `none`:
    - Autonomous war (`declare_war`): requires `existence_status == "active"`, `is_at_war == false`, `has_nap == false`, `has_alliance == false`, `opinion <= -60.0` (`WAR_MAX_OPINION`), `military_power >= 65.0` (`WAR_MIN_MILITARY_POWER`), `stability >= 50.0` (`WAR_MIN_STABILITY`), and either `strategic_goal == "military_expansion"` or (`type == "emerging_power"` and `strategic_goal == "consolidate_power"`). Pre-ascension `neutral_tribe`, unascended `consolidate_power`, and `trade_dominance` factions cannot autonomously declare war.
    - Autonomous peace (`sign_peace`): requires `is_at_war == true`, `existence_status` in `["active", "in_exile"]` (`eliminated` factions never execute diplomacy), and either `military_power <= 20.0` (`PEACE_MAX_MILITARY_POWER`) or `stability <= 25.0` (`PEACE_MAX_STABILITY`).
  - Execution & daily simulation integration in `FactionManager`:
    - Added `get_faction_diplomatic_decision(faction_id)`, `evaluate_all_diplomatic_decisions()`, `get_faction_last_diplomacy_day(faction_id)`, `set_faction_last_diplomacy_day(faction_id, day)`, `execute_faction_diplomatic_action(faction_id, day, decision_override)`, and signals `diplomatic_action_evaluated(faction_id, decision_data)` and `diplomatic_action_executed(faction_id, execution_result)`.
    - Routes `declare_war` through `FactionManager.declare_war(faction_id)` and `sign_peace` through `FactionManager.propose_treaty(faction_id, "peace")` so existing war/peace signals, opinion/disposition updates, and `BattleCampaignManager` raid scheduling/cancellation work seamlessly.
    - Executes autonomous diplomacy in sorted faction-ID order **before** daily strategic economic actions in `FactionManager.update_daily_simulation(day)` with per-faction `_last_diplomacy_days` guards preventing same-day war/peace oscillation or duplicate evaluations.
  - Save/Load persistence & fail-closed validation in `SaveManager`:
    - Persists `last_diplomacy_days` under `factions.strategy_executor.last_diplomacy_days` (`SAVE_SCHEMA_VERSION = 1`), validates `[1, 36500]` and `<= game_clock.current_day` fail-closed before world mutation, filters future days in `FactionManager.deserialize_executor_state()`, and preserves full legacy save compatibility.
  - In-Game HUD notifications (`scripts/ui/hud.gd`):
    - Connected `peace_signed` and enhanced `war_declared` in `HUD.set_faction_manager()` to display Vietnamese event banners with the faction's localized name (`"Chiến Tranh!"`, `"Hòa Bình Lập Lại!"`) and refresh the Diplomacy UI.
  - Dedicated automated test suite `scripts/test/test_faction_diplomacy_ai.gd` covering TC-FDIP.1 through TC-FDIP.16 (16/16 tests passed, 437 checks passed, Exit Code 0).

### [Package 1S] - 2026-10-23
#### Added
- Deterministic Faction Strategic Intent Execution (`FactionStrategyExecutor`, `FactionManager`, `SaveManager`):
  - Dedicated execution layer `scripts/factions/faction_strategy_executor.gd` decoupled from pure evaluator `FactionStrategyPlanner`:
    - `military_buildup` (`military_expansion`): consumes `10 Metal + 25 Gold`, increases `military_power` by `+5.0` up to ceiling `120.0` (peacetime & wartime).
    - `trade_expansion` (`trade_dominance`): peacetime-only (`REASON_BLOCKED_BY_WAR` during war), consumes `5 Tools`, adds `+30 Gold` (up to `1000` ceiling) and `+2.0 stability` (up to `95.0` ceiling).
    - `community_development` (`community_growth`): consumes `10 Wood + 5 Herbs`, increases `population` by `+1` (up to `80` ceiling) and `+2.0 stability` (up to `90.0` ceiling); coordinates cleanly with pre-ascension `neutral_tribe` `+1` daily settlement growth without depleting non-consumptive ascension reserves.
    - `power_consolidation` (`consolidate_power`): requires post-ascension `emerging_power` status, skips duplicate mutation on the exact ascension day (`REASON_ASCENDED_THIS_TICK`), and on subsequent days consumes `15 Wood + 10 Herbs` to increase `military_power` by `+4.0` (up to `90.0` ceiling) and `stability` by `+2.0` (up to `95.0` ceiling).
  - Daily coordination & idempotency in `FactionManager`:
    - Added `execute_faction_strategic_intent(faction_id, day, context)`, `get_faction_last_executed_day(faction_id)`, and signal `strategic_intent_executed(faction_id, execution_result)`.
    - Integrated daily execution into `FactionManager.update_daily_simulation(day)` in deterministic sorted key order (`neutral_tribe`, `rival_merchant`, `rival_military`) with per-faction `last_executed_days` and `_last_tribe_growth_day` guards preventing same-day repeat execution.
  - Save/Load persistence & fail-closed validation in `SaveManager`:
    - Serializes and restores `factions.strategy_executor` (`last_executed_days`, `last_tribe_growth_day`) with full legacy save fallback and fail-closed rejection of malformed or future execution days (`> game_clock.current_day`).
  - Dedicated automated test suite `scripts/test/test_faction_strategy_execution.gd` covering TC-FEXEC.1 through TC-FEXEC.14 (PASS, Exit Code 0).

### [Package 1R] - 2026-10-22
#### Added
- Deterministic Faction Strategic Decision Engine (`FactionStrategyPlanner`, `FactionManager`):
  - Deterministic Strategic Intent Planning Layer conforming to GDD §10.1 & Scope Decision 1.18:
    - Pure evaluator class `scripts/factions/faction_strategy_planner.gd` translating `FactionData` strategic goals into high-level operational intents without random rolls, hidden biases, or LLM non-determinism.
    - Canonical mapping of strategic goals to intent IDs: `military_expansion` $\to$ `military_buildup`, `trade_dominance` $\to$ `trade_expansion`, `community_growth` $\to$ `community_development`, `consolidate_power` $\to$ `power_consolidation`.
    - Centralized Vietnamese localization helper (`FactionStrategyPlanner.get_intent_label()`) returning `"Tăng cường quân sự"`, `"Mở rộng giao thương"`, `"Phát triển cộng đồng"`, `"Củng cố quyền lực"`, and fallback `"Không xác định"`.
    - Structured intent dictionary payload: `faction_id`, `strategic_goal`, `intent_id`, `eligible`, `reason_code`, and `posture`.
  - Existence Status & Wartime Posture Gating:
    - Only `active` factions receive eligible operational intents (`eligible: true`).
    - Factions in `in_exile` or `eliminated` statuses return `eligible: false` and `intent_id: "none"` with diagnostic reason codes `INELIGIBLE_IN_EXILE` or `INELIGIBLE_ELIMINATED`.
    - Military defeat (0 military power) does not alter existence status or disqualify an active faction.
    - Factions at war (`is_at_war == true`) have posture set to `"wartime"` with reason code `WARTIME_POSTURE`.
    - Unrecognized goals or invalid statuses fail closed with reason codes `ERR_INVALID_GOAL` and `ERR_INVALID_STATUS`.
  - FactionManager Daily Simulation & API Integration:
    - Added signal `strategic_intent_evaluated(faction_id: String, intent_data: Dictionary)`.
    - Factions are evaluated in deterministic alphabetical key order (`sorted_ids.sort()`) during `FactionManager.update_daily_simulation(day)` immediately following emerging faction ascension checks.
    - Added query APIs `FactionManager.get_faction_strategic_intent(faction_id)` and `FactionManager.evaluate_all_strategic_intents()`.
    - Evaluator operations remain strictly immutable and read-only, causing zero side effects on faction attributes, resources, diplomacy, or world state.
  - Dedicated automated test suite `scripts/test/test_faction_strategy_planner.gd` covering TC-FSTRAT.1 through TC-FSTRAT.7 (7/7 tests passed, 147 assertions passed, Exit Code 0).

### [Package 1Q] - 2026-10-20
#### Added
- Faction Strategic Profiles & Existence Status (`FactionData`, `FactionManager`, `SaveManager`, `HUD`):
  - Added Strategic Goal and Existence Status data model to `FactionData` conforming to GDD §10.1 & §10.5:
    - Stable English internal IDs: `military_expansion`, `trade_dominance`, `community_growth`, `consolidate_power` for strategic goals; `active`, `in_exile`, `eliminated` for existence statuses.
    - Centralized Vietnamese localization helpers (`FactionData.get_strategic_goal_label()` and `FactionData.get_existence_status_label()`) preventing raw identifier leakage to UI.
    - Initial default mappings: `rival_military` mapped to `military_expansion` and `active`; `rival_merchant` mapped to `trade_dominance` and `active`; `neutral_tribe` mapped to `community_growth` and `active`.
  - Ascension Integration:
    - When `neutral_tribe` evolves into an `emerging_power` in `FactionManager.update_daily_simulation()`, its strategic goal mutates to `consolidate_power` while status remains `active`.
    - Ascension signal remains strictly single-emission and idempotent.
  - Fail-Closed Persistence & Schema Validation:
    - `SaveManager.serialize_world_state()` records `strategic_goal` and `existence_status` for all factions.
    - `SaveManager.validate_save_data()` validates strategic goals and existence statuses against canonical allowed sets, failing closed on unrecognized values.
    - `SaveManager.apply_loaded_state_to_world()` restores profiles cleanly and applies robust fallbacks on legacy saves without these fields.
  - In-Game HUD Integration:
    - HUD diplomacy cards display Vietnamese labels for strategic goal and existence status (`"Mục tiêu: %s | Trạng thái: %s"`).
    - Automatically refreshes diplomacy cards upon faction evolution or reload.
  - Dedicated automated test suite `scripts/test/test_faction_profiles.gd` covering TC-FPROF.1 through TC-FPROF.9 (9/9 tests passed, Exit Code 0).

### [Package 1P] - 2026-10-20
#### Added
- Emerging Faction Ascension Gates (`FactionManager`, `SaveManager`, `HUD`):
  - Authoritative Ascension Gates conforming to GDD §10.3 and deterministic scope decisions:
    - Time Gate: Simulation day $\ge 10$ (`ASCENSION_MIN_DAY = 10`).
    - Population Gate: Neutral tribe population $\ge 45$ (`ASCENSION_MIN_POPULATION = 45`).
    - Essential Resource Gates: Wood stock $\ge 60$ (`ASCENSION_MIN_WOOD = 60`) and Herbs stock $\ge 30$ (`ASCENSION_MIN_HERBS = 30`).
    - Stability Gate: Internal stability $\ge 50.0$ (`ASCENSION_MIN_STABILITY = 50.0`).
  - Helper methods added to `FactionManager`:
    - `has_emerging_power() -> bool`: Verifies single emerging power limit across active factions.
    - `can_emerging_faction_ascend(day: int) -> bool`: Atomically checks presence of neutral tribe, single emerging power rule, population, time, stability, and resource requirements without side effects.
  - Non-consumptive resource check:
    - Ascension validates prerequisite resources without deducting wood or herbs from the tribe.
  - Evolutionary outcome and idempotency:
    - Neutral tribe evolves into an emerging power: `type = "emerging_power"`, `name = "Liên Minh Rừng Thiêng"`, `military_power = 55.0`, `stability = 85.0`.
    - Emits `emerging_faction_ascended(tribe.id, tribe.name)` exactly once.
    - Subsequent simulation days fail the `type == "neutral_tribe"` check, preventing duplicate state mutations or repeated signal emissions.
  - Persistence & Backward Compatibility:
    - `SaveManager.serialize_world_state()` now preserves the `resources` dictionary for all registered factions.
    - `SaveManager.apply_loaded_state_to_world()` restores `name`, `type`, and `resources` if present, maintaining complete compatibility with legacy saves.
  - In-Game HUD Integration:
    - Connected `emerging_faction_ascended` in `HUD.set_faction_manager()` to display a Vietnamese announcement banner (`"Thế Lực Mới Nổi! Liên Minh Rừng Thiêng đã chính thức trỗi dậy thành một cường bang mới!"`) and dynamically refresh diplomacy cards.
  - Dedicated automated test suite `scripts/test/test_emerging_faction_ascension.gd` covering TC-EMERGE.1 through TC-EMERGE.11 (11/11 tests passed, Exit Code 0).

### [Package 1O] - 2026-10-20
#### Added
- Post-Battle Diplomatic Consequences (`BattleCampaignManager`, `FactionManager`, `FactionData`):
  - Connects combat outcomes to foreign relations per GDD §10.2 and §10.4:
    - Player-led offensive campaigns apply a -8.0 opinion penalty (`FactionManager.OPINION_PENALTY_OFFENSIVE_CAMPAIGN`) to target factions upon battle resolution.
    - Enemy settlement raids apply a -10.0 opinion penalty (`FactionManager.OPINION_PENALTY_SETTLEMENT_RAID`) to attacking factions upon raid resolution.
  - Added `FactionManager.modify_opinion(faction_id: String, delta: float) -> Dictionary`:
    - Clamps opinion safely within canonical `[-100.0, 100.0]` range.
    - Emits `relation_changed` signal exactly once per battle consequence.
    - Preserves hostile disposition lock during active war.
  - Added `FactionData.recalculate_disposition()`:
    - Dynamically recalculates faction disposition based on opinion thresholds (<= -40.0 Hostile, < 25.0 Neutral, < 75.0 Friendly, >= 75.0 Allied) when not at war.
    - Enforces strictly `HOSTILE` disposition while `is_at_war == true`.
    - Automatically updates disposition when signing peace via `FactionData.sign_peace()` (`change_opinion(20.0)` flow).
  - Fail-closed transactional safety:
    - Ineligible offensive campaigns (zero soldiers, garrisoned at base, marching in transit, non-war factions, zero enemy power) apply zero diplomatic mutations and emit zero signals.
    - Ineligible raids (not due, already processed, non-existent) apply zero diplomatic mutations and emit zero signals.
  - Integrated Persistence & Idempotency:
    - Save/load roundtrip via `SaveManager` restores post-battle opinions and dispositions with zero signal emissions.
    - Repeated loads execute idempotently without reapplying opinion penalties or altering army markers.
  - Dedicated automated test suite `scripts/test/test_battle_diplomacy_consequences.gd` covering TC-DIPLO.1 through TC-DIPLO.11 (11/11 tests passed, Exit Code 0).

### [Package 1N] - 2026-10-20
#### Added
- Player-Led Abstract Offensive Campaigns (`BattleCampaignManager` & `HUD`):
  - Added offensive campaign capability in `BattleCampaignManager`: `can_launch_offensive_campaign(target_faction_id)` and `launch_offensive_campaign(target_faction_id, custom_seed)`.
  - Authoritative offensive gating rules: requires standing army soldiers $\ge 1$; field deployment status (`movement_state == MovementState.IDLE_AT_FIELD` and `current_cell != rally_cell`); target faction exists, is at war (`is_at_war == true`), and has military power > 0.0. Fails closed with informative Vietnamese diagnostics on invalid conditions.
  - Deterministic battle resolution via `BattleResolver.resolve_battle()`: uses derived seed `(world_seed * 37 + cur_day * 103 + hash(target_faction_id) + sequence * 19) & 0x7FFFFFFF` with caller force dictionary duplication to ensure immutability.
  - Symmetrical force translation: enemy force derived from `fac.military_power / 30.0` (clamped 1..20 troops) with equipment tier 2 for rival military and morale mapped from stability. Attacker force derived from player army count and supplied combat morale.
  - Atomic battle state mutations: player casualties deducted via `PlayerArmyManager.remove_casualties()`; enemy military power reduced by `casualties * 30.0` (clamped $\ge 0.0$).
  - Post-battle army normalization: complete casualty wipeout normalizes army to clean `GARRISONED` status at home `rally_cell`; surviving soldiers remain deployed in field (`IDLE_AT_FIELD`) without teleportation.
  - Signal architecture: added `offensive_campaign_resolved(report, context)` and wired into `battle_resolved(report, context)` with `context.is_offensive == true`.
  - In-Game HUD offensive battle report integration: added `AttackCampaignBtn` (`"⚔️ Mở Chiến Dịch Tấn Công"`) in `ArmyPanel` and `attack_btn` (`"⚔️ Tấn Công"`) in hostile faction diplomacy cards; rich Vietnamese event banners detailing casualties, troop counts, combat scores, and remaining enemy power.
  - Save/load persistence & schema validation: serialized `offensive_sequence` in `BattleCampaignManager.serialize()`; updated `SaveManager.validate_save_data()` to enforce schema types and non-negativity for `battle_campaign.offensive_sequence` and `campaign_sequence`.
  - Dedicated automated test suite `scripts/test/test_offensive_campaign.gd` covering TC-OFFENSE.1 through TC-OFFENSE.14 (14/14 tests passed, Exit Code 0).
  - Review Fix (Integrated SaveManager World Lifecycle & Schema Hardening):
    - Extended `SaveManager.validate_save_data()` to validate `pending_raids` and `processed_raids` dictionaries when present under `battle_campaign`.
    - Strengthened `TC-OFFENSE.12` in `scripts/test/test_offensive_campaign.gd` with a live `world_instance` integration test covering Parts A-D:
      - Part A: Set up live army deployed `IDLE_AT_FIELD` away from rally cell, configured hostile `rival_military` with positive military power, scheduled pending settlement raid, attached signal spy to `offensive_campaign_resolved`, launched valid offensive campaign, and captured post-battle state (surviving troops, `IDLE_AT_FIELD` status, reduced military power, incremented sequence, intact raid schedule, resource snapshot).
      - Part B: Serialized world state via `SaveManager.serialize_world_state()` and asserted valid schema, matching post-battle soldier count and field coordinates, updated faction power, sequence, and preserved raid schedule.
      - Part C: Perturbed live in-memory values (army count/state, faction power/war status, sequence, raids, resource stocks), cleared signal emission tracker, restored state via `SaveManager.apply_loaded_state_to_world()`, and asserted 100% restoration of post-battle values, intact raid schedule, matching resources, and strictly 0 additional `offensive_campaign_resolved` signal emissions (world loading restores state without replaying battles).
      - Part D: Applied loaded state a second time to verify double-load idempotency: zero additional signal emissions, zero duplicated `ArmyMarker` nodes (count $\le 1$), and zero extra casualties or deductions.

### [Package 1M] - 2026-10-20
#### Added
- Player Army Marching & Garrison Deployment (`PlayerArmyManager` & `ArmyMarker`):
  - Added movement state machine to `PlayerArmyManager`: `MovementState` enum (`GARRISONED = 0`, `MARCHING = 1`, `IDLE_AT_FIELD = 2`).
  - Grid navigation and discrete pathing: integrates existing `GridNavigation` A* pathfinder on 64×64 logical grid, enforcing collision and water avoidance with discrete step pacing (`CELL_STEP_DURATION = 0.5` seconds per tile).
  - Home settlement rally point: derives default rally point at Town Hall south plaza (`Vector2i(32, 33)`) with deterministic outward radial search fallback.
  - Authoritative movement commands: `order_move(target_cell)`, `cancel_move()`, and `order_return_home()` with atomic fail-closed rejection on out-of-bounds, blocked cells, zero soldiers, or same-cell orders.
  - Dynamic obstruction rerouting: mid-transit obstruction detection recalculates alternative path; safely halts and transitions to `IDLE_AT_FIELD` if route is completely trapped.
  - Simulation clock scaling: movement accumulator scales proportionally with simulation speeds (1x, 2x, 3x) and strictly freezes during pause (`TimeManager.is_paused()`).
  - Defense eligibility gating: standing army units participate in settlement defense (`construct_defending_force`) only when garrisoned at home rally point (`is_defense_eligible()`); absent armies are excluded from defense battles and take zero raid casualties.
  - Recruitment gating: recruiting soldiers requires army to be garrisoned at home rally point; returns clear Vietnamese diagnostics if deployed in field or marching.
  - Auto-recovery on wipeout: total casualty wipeout automatically recovers army to clean `GARRISONED` state at home rally point with cleared path.
  - Visual Army Marker (`ArmyMarker`): lightweight dimetric isometric 2:1 visual marker in `WorldView` with Y-sorting, ground-contact foot pivot `(-12, -30)`, live troop count label (`🛡️` for garrison, `⚔️` for field), and smooth position interpolation. Hides when army count is zero.
  - In-Game HUD military enhancements: added `DeploymentLabel` with Vietnamese status, `MoveArmyBtn` (`"🚩 Điều động hành quân"`), `ReturnHomeBtn` (`"🏠 Rút về căn cứ"`), map click-to-move targeting mode with cursor hover info, and ESC key cancellation.
  - Save/load persistence & fail-closed validation: extended `SaveManager` to serialize/deserialize all movement fields under `"player_army"`; added rigorous bounds/type/enum validation; double-load idempotency with zero duplicate nodes; legacy save compatibility.
  - Review fix hardening (Package 1M Review Fix & Final Review Fix):
    - Save validator route continuity & cross-field invariants: `SaveManager.validate_save_data()` enforces cardinal adjacency ($|dx| + |dy| == 1$) between successive route waypoints, adjacency of first waypoint to `current_cell`, final waypoint equality with `destination_cell`, and strict state invariants (marching requires non-empty path with dest != cur; garrisoned requires empty path with cur == rally and dest == rally; idle_at_field requires empty path with dest == cur and cur != rally).
    - Deserialization walkability validation & safe route recovery: `PlayerArmyManager.deserialize()` validates rally cell, current cell, destination cell, and route waypoints against `GridNavigation.is_cell_walkable()`. Dynamically repairs obstructed paths around blocked waypoints without teleporting; safely halts at current position if destination is blocked or unreachable; normalizes field garrison anomalies to `IDLE_AT_FIELD`.
    - Return-home before first movement step: `PlayerArmyManager.order_return_home()` cleanly cancels outbound march orders when army is still logically at `rally_cell`, clears route, resets destination to rally, sets `GARRISONED`, and immediately restores defense eligibility with zero teleportation.
    - Mutually exclusive input modes: starting army targeting in `HUD` cancels active building placement in `WorldView` and hides ghost preview; selecting a building in HUD cancels active army targeting; pressing ESC cancels building placement cleanly.
    - HUD move contract alignment: `PlayerArmyManager.order_move()` returns `"steps"` and `"path_length"`, ensuring HUD event banners display the actual positive step count.
    - Reload resource and upkeep assertions: strengthened TC-MOVE.20 to capture live world resource stocks, capacities, active population, and army persistence fields (`last_upkeep_day`, `soldier_count`, `is_supplied`) before load, asserting exact preservation and zero unintended deductions across real `SaveManager` double loads, and proving via isolated `deserialize()` test that deserialization causes zero resource deductions.
    - Accurate return-home actions & feedback: `PlayerArmyManager.order_return_home()` returns structured `"action"` identifiers (`"canceled_at_rally"`, `"already_garrisoned"`, `"returned_to_garrison"`, `"marching_home"`). `HUD._on_return_home_btn_pressed()` provides differentiated Vietnamese event banners for canceling at rally, already garrisoned, and marching home. Verified in TC-MOVE.29 and TC-MOVE.32.
  - Automated test suite `scripts/test/test_army_movement.gd` covering TC-MOVE.1 through TC-MOVE.32 (32/32 tests passed, Exit Code 0).

### [Package 1L] - 2026-10-19
#### Added
- Player Army Recruitment & Upkeep System (`PlayerArmyManager`):
  - Abstract standing army model separate from civilian `CitizenController` units, eliminating population inflation and civilian labor drain while expanding settlement defense capabilities.
  - Barracks capacity derivation: 5 soldiers per active Barracks structure (`ARMY_CAPACITY_PER_BARRACKS = 5`), dynamically responding to construction, damage, and destruction.
  - Atomic recruitment transactions: costs 20 Gold, 2 Metal, and 5 Food per soldier with fail-closed all-or-nothing reservations.
  - Daily food upkeep simulation: consumes 1 Food per soldier on simulation day ticks (`00:00` Game Time), gated by `last_upkeep_day` for strict daily idempotency.
  - Starvation & supply state machine: insufficient food marks army unsupplied without deleting soldiers or draining partial food stocks. Restoring food automatically recovers supplied status on subsequent day ticks.
  - Combat morale scaling: supplied soldiers fight at 70.0 morale (`ARMY_MORALE_SUPPLIED`); unsupplied soldiers fight at 45.0 morale (`ARMY_MORALE_UNSUPPLIED`).
  - Defending garrison force integration: `BattleCampaignManager.construct_defending_force()` combines recruited army units and living civilian guards with weighted average combat morale.
  - Casualty absorption priority: settlement battle casualties deduct from recruited army first, preserving civilian guards until standing army reserves are exhausted. Abstract army casualties do not trigger civilian death events.
  - Save/load persistence: full serialization and deserialization of `soldier_count`, `is_supplied`, and `last_upkeep_day` under `"player_army"` in `SaveManager` with legacy save compatibility and schema validation.
  - HUD Military Interface: added `MilitaryBtn` (`"⚔️ Quân Đội (U)"`) on `BottomBar`, non-modal `ArmyPanel` dialog with live stats, barracks capacity, upkeep rate, recruitment button with failure diagnostics, and hotkey `U`/`ESC` bindings.
  - Dedicated automated test suite `scripts/test/test_player_army.gd` covering TC-ARMY.1 through TC-ARMY.30 (PASS, Exit Code 0), and extension of `scripts/test/test_live_battle_loop.gd` with TC-LB.4C and TC-LB.7B (PASS, Exit Code 0).
#### Fixed & Hardened
- Real citizen death lifecycle: `CitizenController` implements canonical `die(reason)` method releasing active jobs to `AVAILABLE`, clearing worker assignment, clearing path, and emitting `citizen_died`; wired to `BattleCampaignManager` and verified in TC-ARMY.28 with live `WorldView` integration, asserting job release, registry cleanup, single combat death event, idempotency on repeat calls, and civilian isolation from abstract army casualties.
- Citizen death signal emission idempotency: hardened `CitizenController.die()` to track `_death_processed` and return immediately without re-emitting `citizen_died` when the citizen is already dead and cleanup is complete. If cleanup is incomplete on entry, cleanup is completed safely before emitting the single effective death signal. Strengthened `TC-ARMY.28` in `test_player_army.gd` with an independent probe listener to assert exactly one signal emission, zero duplicate emissions on repeated `die()` calls, and zero signals from abstract army casualties.
- Guard job release assertion tightening: updated `TC-ARMY.28` post-death assertion in `test_player_army.gd` to strictly enforce both exact conditions: `test_job.state == JobManager.JobState.AVAILABLE` and `test_job.worker_id == ""`.
- Load side-effect verification: strengthened TC-ARMY.29B and TC-ARMY.30B to verify non-default army state survival across Save -> Load -> Save roundtrips, double-load idempotency (zero duplicated soldiers, citizens, HUD nodes, or signal connections), zero resource deductions or extra upkeep on load, resource stock consistency, same-day upkeep idempotency, and Package 1K campaign state preservation across normal and legacy loads.
- Fail-closed malformed clock day validation: `SaveManager.validate_save_data()` enforces that if `game_clock` is present, it must be a Dictionary and `current_day` must be a valid integer $\ge 1$; rejects malformed clock days (string, float, zero, negative, array, non-dict) fail-closed; verified `apply_loaded_state_to_world()` rejects invalid save input before any destructive world reconstruction begins.
- Dynamic Barracks capacity & HUD synchronization: wired `complete_construction`, `cancel_construction_project`, `set_building_state`, and `demolish_building_project` in `WorldView` to notify `PlayerArmyManager.notify_capacity_changed()` and update HUD `ArmyPanel` in real time, preserving recruited soldiers across damage/demolition; formatted recruitment costs dynamically from `EconomyConfig.ARMY_RECRUIT_COST` and `EconomyConfig.RESOURCE_NAMES_VI`.
- Comprehensive integration testing: verified all 32 tests in `test_player_army.gd` pass with Exit Code 0.


### [Package 1K] - 2026-10-19
#### Added
- Live Settlement Defense Battle Loop (`BattleCampaignManager`):
  - Authoritative settlement raid scheduler: automatically schedules an incoming raid 3 game-days after war is declared, followed by recurring raids every 5 game-days while the hostile faction maintains positive military strength.
  - Diplomatic treaty integration: signing peace immediately cancels any pending raids and releases hostile intent cleanly.
  - Authoritative attacking force modeling: maps `FactionData.military_power` to abstract troops (clamped 1..20), equipment tier (tier 2 for rival military, tier 1 otherwise), and morale derived from stability.
  - Defending force construction: builds the settlement defense force from living citizens assigned to the Guard role, gated strictly by an active Barracks and including available resource stock.
  - Zero-troop & casualty edge-case safety in `BattleResolver.resolve_battle()`: handles 0 vs 0 (stalemate with 0 casualties), unopposed raids against undefended settlements (attacker victory with 0 casualties on both sides and resource plunder), and strictly clamps casualties to not exceed initial force size.
  - Exactly-once world outcome mutation: removes lost guards through `citizen_died` signal with job cleanup, reduces attacking military power by 30.0 per casualty without going negative, and deducts resource plunder respecting available stock without touching reserved inventory.
  - Strict idempotency: stable raid identifiers prevent repeat processing or duplicate casualties/plunder on re-runs or save/load.
  - Save/load persistence: serializes and restores campaign raid state via `SaveManager` (`"battle_campaign"` section) with full legacy save compatibility.
  - Player-facing feedback: HUD banners and Diplomacy panel cards display upcoming raid days, detailed battle outcome summaries, and peace cancellations.
  - Automated test suite `scripts/test/test_live_battle_loop.gd` covering TC-LB.1 through TC-LB.19 (PASS, Exit Code 0).
#### Fixed & Hardened
- Overdue raid processing: `BattleCampaignManager.process_daily_raids()` passes current simulation day to resolution, reports the actual resolution day, and schedules next raid relative to current day (TC-LB.15).
- Transactional plunder & in-flight guard: pre-validates plunder plan against available stock, uses `reserve_cost()` / `commit_cost()` to protect reserved stock; fails closed upon reservation failure; blocks re-entrant calls via `_in_flight_raids` (TC-LB.16).
- Fail-closed non-transactional plunder handling: removed non-atomic `consume_resource()` loop fallback; strictly requires transactional `reserve_cost()` + `commit_cost()`, failing closed with zero plunder reported and zero resources deducted if transaction APIs are missing (TC-LB.16 Subcheck D).
- Citizen death notification accuracy & idempotency: `WorldView._on_citizen_died()` checks `status_reason` to trigger `Chiến Binh Tử Trận` for combat casualties while preserving `Tang Lễ Vương Quốc` for starvation/exhaustion deaths; tracks `deceased_citizen_ids` to idempotently ignore repeated death calls for the same citizen ID and rejects non-existent IDs without emitting spurious events or modifying population (TC-LB.17).
- Real daily scheduling with `TimeManager`: verified end-to-end integration via `TimeManager.day_passed` signal, zero premature resolution, single execution on due day, and cancellation on peace (TC-LB.18).
- Legacy save campaign state reset: `SaveManager.apply_loaded_state_to_world()` invokes `campaign_mgr.deserialize({})` when `"battle_campaign"` is omitted or empty, purging in-flight, pending, and processed raids to guarantee stale raids do not execute on day advance (TC-LB.19).

### [Package 1J] - 2026-10-19
#### Added
- Authoritative Settlement Battle API (`BattleResolver.resolve_settlement_battle`):
  - Directly connects abstract deterministic combat resolution to live settlement world data (`WorldGenerator.WorldData`).
  - Automatically queries `BuildingSystem.calculate_fortification_level(defender_world_data)` to compute fortification levels 0..3 from active Palisade fortifications (+30% defender combat score per level).
  - Enforces authoritative fortification levels by overwriting any caller-omitted or stale fortification values in `defender_force`.
  - Implements fail-closed behavior: invalid or null `defender_world_data` automatically defaults to fortification level 0 (+0% bonus) and reports `has_settlement_context == false`.
  - Guaranteed caller input immutability: deep clones `attacker_force` and `defender_force` via `.duplicate(true)`, preventing unintended mutations or resource leakage on caller state.
  - Enriched `BattleReport.details` with `"fortification_level"`, `"fortification_bonus"`, and `"has_settlement_context"`.
  - Full backward compatibility: existing non-settlement calls to `BattleResolver.resolve_battle()` retain abstract combat capabilities without regression.
  - Dedicated automated test suite `scripts/test/test_battle_fortification.gd` verifying all 12 test conditions (TC-BF.1 through TC-BF.12) with 100% pass rate.

### [Package 1I] - 2026-10-18
#### Added
- Buildable Palisade defensive structure (Tường Rào Phòng Ngự) adhering to GDD Section 7.3:
  - Authoritative blueprint `palisade` in `EconomyConfig.BLUEPRINTS`: 1x1 diamond footprint, construction cost 4 Wood + 2 Stone, 3.0h construction time, 0 workers, empty storage, no production jobs.
  - Dedicated pixel art asset `assets/buildings/bld_palisade.png` (32x36 px) conforming to the authoritative 27-color fantasy palette, NW lighting, and 2:1 dimetric perspective with log ramparts and defensive spikes.
  - Full construction lifecycle integration: starts in `under_construction` state with initial progress 0.0h, allocates 2 concurrent builder jobs, renders with amber modulate scaffolding (`Color(0.8, 0.7, 0.5, 0.7)`), and cleanly resets modulate on completion.
  - Construction cancellation policy refunding 50% blueprint costs atomically (+2 Wood, +1 Stone) with storage capacity pre-validation, clearing footprint occupancy and builder jobs.
  - Navigation grid obstacle integration: `GridNavigation` treats completed and under-construction palisades as solid unwalkable obstacles (`is_cell_walkable == false`), forcing citizens and pathfinding to route around.
  - Settlement fortification calculation: `BuildingSystem.calculate_fortification_level(world_data)` and `BattleResolver.calculate_settlement_fortification_level(world_data)` deduplicate active palisades and calculate fortification level 0..3 (0: 0 palisades, 1: 1-4 palisades, 2: 5-9 palisades, 3: 10+ palisades), integrating with `BattleResolver` combat score calculation (+30% per level).
  - HUD Build Menu integration: Added dedicated `PalisadeBtn` under `scenes/ui/hud.tscn` with Vietnamese label `🛡️ Tường Rào (4W 2S)` and ghost placement preview with proper texture and offset `Vector2(-16.0, -28.0)`.
  - Save/load persistence: Full serialization and deserialization of active and under-construction palisades without duplicate nodes, duplicate jobs, or secondary resource deductions.
  - Automated test suite `scripts/test/test_palisade.gd` covering TC-PA.1 through TC-PA.7 (PASS, Exit Code 0).
#### Changed / Hardened
- Build Menu Panel Geometry Fix: Adjusted `BuildMenuPanel` layout in `scenes/ui/hud.tscn` (`offset_top = -466.0`, `offset_bottom = -56.0`, height 410 px; `offset_left = -340.0`, `offset_right = 340.0`, width 680 px), ensuring all 6 grid rows (11 building buttons) and `CloseBuildBtn` are fully enclosed without clipping, maintaining 8 px vertical clearance above `BottomBar` and horizontal viewport centering. Added automated geometry regression assertions in `test_palisade.gd` TC-PA.7 verifying enclosing rects, clearance, and close button dismissal.

### [Package 1H] - 2026-10-18
#### Added
- Full builder construction lifecycle adhering strictly to GDD Section 7.3:
  - Player-placed buildings now start in `under_construction` state with `construction_progress = 0.0` and `construction_hours` defined per blueprint in `EconomyConfig.BLUEPRINTS`.
  - Immediate 100% footprint occupancy and atomic resource reservation/deduction upon site placement (fail-closed on null `ResourceManager`).
  - Dynamic builder jobs (`job.type == "builder"`) with concurrent worker capacity scaling by footprint (1x1: 2, 2x2: 3, 3x3: 4), bounded by walkable perimeter cells.
  - Real builder work loop in `CitizenController` advancing shared project progress by `delta_hours` per working builder; respects pause and time speed (1x, 2x, 3x).
  - Centralized idempotent completion transition (`complete_construction`) unlocking building operational features (workplace channels, guard posts, research UI, watchtower vision, housing capacity, storehouse capacity) and resetting amber scaffolding modulate.
  - Construction cancellation policy refunding 50% blueprint costs atomically, clearing footprint occupancy and visual node, and removing builder jobs.
  - Amber scaffolding visual modulate `Color(0.8, 0.7, 0.5, 0.7)` and dynamic HUD hover progress percentage `[Đang xây: X%]`.
  - Save/load persistence restoring exact construction progress and hours, zero duplicate jobs/nodes, zero deduction on reload, and legacy save compatibility.
  - Comprehensive automated test suite `scripts/test/test_construction.gd` covering TC-CON.1 through TC-CON.6 (PASS, Exit Code 0).
#### Changed / Hardened
- Strict construction completion threshold enforcement: `BuildingSystem.complete_building()` and `WorldView.complete_construction()` strictly refuse completion unless `state == "under_construction"`, `construction_hours > 0`, and `construction_progress >= construction_hours - 0.001`.
- Fail-closed progress delta validation: `advance_construction()` safely ignores negative or NaN/inf deltas without decrementing progress.
- Watchtower vision state filtering: `WorldView._on_simulation_hour_passed()` now only grants vision for watchtowers with `state == "active"`; paused, damaged, or under-construction towers do not grant vision.
- Job prefix collision immunity: `JobManager.job_matches_building()` enforces exact match or separator-aware prefix matching (`building_id + "_"`), preventing false-positive cancellation/cleanup collisions between neighboring buildings (e.g., `bld_house_28_28` vs `bld_house_28_280`).
- Safe cancellation refund storage guarantee: `BuildingSystem.cancel_construction()` performs all-or-nothing capacity validation before modifying world state, refusing cancellation if central storage cannot hold the full 50% refund.
- Save/load schema integrity: `SaveManager.validate_save_data()` validates building array types, blueprint names, coordinate bounds, positive finite hours, progress ranges, and valid state enums before world state deserialization begins.
- Idempotent construction job registration: `WorldView.register_construction_jobs()` verifies `state == "under_construction"`, preserves existing valid builder jobs on repeated calls up to concurrent worker capacity, handles stale jobs safely, and isolates overlapping textual prefix IDs.
- Blueprint footprint & integer validation: `SaveManager.validate_save_data()` strictly requires saved building footprints to match authoritative blueprints (rejecting mismatched sizes like 3x3 houses), requires grid coordinates and dimensions to be valid integers (rejecting fractional values), and gracefully handles legacy saves omitting size fields.
- Fail-closed storage effects on completion: `BuildingSystem.complete_building()` refuses activation if blueprint grants storage capacity but `ResourceManager` is missing, and guards against duplicate storage bonuses via `storage_applied`.
- Construction job perimeter validity & worker safety: In `WorldView.register_construction_jobs()`, enforced that retained builder jobs must have their `target_cell` contained in the building's computed perimeter, deduplicated jobs by `target_cell` while preserving active assignments (`IN_PROGRESS`/`RESERVED`), safely released displaced/cancelled workers to `IDLE` without leaving orphaned job references, and strictly capped retained and new jobs to `min(worker_capacity, valid_perimeter_cell_count)`. Added TC-CON.2 Subchecks A–D verifying stale cell cleanup, duplicate cell deduplication, worker safety, strict idempotency, and project isolation.
- Unrelated citizen assignment preservation & exact project ownership: In `WorldView._safe_cleanup_construction_job()`, only clear `active_job` and interrupt the worker when their `active_job` actually matches the job being removed, leaving citizens assigned to unrelated valid jobs completely undisturbed even if an invalid job's `worker_id` points to them. For citizens whose `active_job` is null but who are stranded in a job-related state, safely transition them to `IDLE` with cleared path. In `WorldView.register_construction_jobs()`, enforced strict project ownership (`j.type == "builder" and j.target_building_id == b_id`) to prevent cross-building job adoption or removal for projects with delimited prefixes (such as `bld_house_15_15_annex`). Added TC-CON.2 Subchecks E, F, G verifying assignment preservation, stale cleanup, and project isolation.

### [Package 1G] - 2026-10-18
#### Added
- Buildable Barracks (Doanh Trại) with 3x3 footprint, cost (25 Wood, 20 Stone, 5 Metal), and 2 guard capacity slots.
- Dedicated 96x80 pixel art sprite `assets/buildings/bld_barracks.png` conforming to 27-color fantasy palette with NW lighting.
- Active Barracks detection via `BuildingSystem.is_barracks_active(world_data)` strictly requiring `state == "active"`.
- Unique perimeter sentry cell calculation via `BuildingSystem.find_perimeter_cells(origin, size, world_data, max_count)`.
- Guard role gating at UI and controller levels:
  - Role dropdown item 7 disabled/annotated when no active Barracks exists.
  - Fail-closed role assignment preventing Guard assignment without an active Barracks.
  - Inactive Barracks duty release: guards pause duty with status "Cần Doanh Trại đang hoạt động" without losing their role.
- Deterministic guard duty loop in `CitizenController` with `State.GUARDING`, time pause safety, and urgent needs release (hunger >= 70, fatigue >= 85).
- Save/load persistence hardening attaching barracks checker to restored citizens, with zero node/job duplication.
- Comprehensive automated test suite `scripts/test/test_barracks.gd` covering TC-BR.1 through TC-BR.7 (PASS, Exit Code 0).

### [1.0.0-rc1] - 2026-10-12
#### Added
- Phase 9 Polish, Asset Integration, Stress Test & Release Candidate completed:
  - Procedural 16-bit audio synthesis subsystem `scripts/audio/audio_manager.gd` generating 8 crisp retro sound streams (UI click, building thud, error buzz, tech arpeggio chime, coin trade ding, victory fanfare, crisis alarm, and looping pastoral ambient music) with polyphonic playback pool and volume/mute controls.
  - 100-citizen simulation stress test `scripts/test/test_stress_100_citizens.gd` maintaining ~145 FPS at 1× and 3× speed (mean frame time 6.87 ms, beating the $\ge 60$ FPS threshold).
  - Extended multi-day simulation verified across 72 continuous simulation hours (3 game days) in 238.65 ms without stalls or memory leaks.
  - Windows Desktop release export presets configured in `export_presets.cfg`.
  - Comprehensive non-programmer manual verification guide in `docs/SMOKE_TEST_CHECKLIST.md`.
  - Full 12-suite regression test matrix passing 100% with Exit Code 0.
  - Verified visual fidelity adhering strictly to `docs/ASSET_STYLE_GUIDE.md` across Main Menu and 64×64 WorldView scenes.

### [0.9.0] - 2026-10-12
#### Added
- Phase 8 Robust Save/Load & Persistence Hardening completed:
  - `scripts/persistence/save_manager.gd`: versioned JSON schema (v1), atomic disk writes (`.tmp` → `.json`), `.bak` auto-backup on overwrite, schema/section validation, graceful corruption rejection, automatic `.bak` fallback recovery.
  - Full world state serialization: clock, resources (stock + capacities), buildings (id/type/cell/size/state/health), citizens (id/name/role/cell/stats), research progress, faction diplomatic states, POI claim states, victory/collapse progress, fog-of-war explored cells.
  - Zero-duplication reconstruction in `apply_loaded_state_to_world()`: clears old scene nodes before restoring from save data.
  - In-Game Pause Menu: "💾 Lưu Thế Giới" and "📂 Tải Bản Lưu" buttons with success/error status feedback label.
  - Main Menu: "📂 Tải Thế Giới" button dynamically enabled if `user://saves/world_save.json` or `.bak` exists.
  - Daily autosave: configurable interval (default: every 1 game day) with EventManager notification.
  - Automated test suite `scripts/test/test_save_load.gd` (TC-8.1, TC-8.2, TC-8.3 all passed):
    - TC-8.1: save→load→save canonical equivalence (24 citizens, 8 buildings, fog-of-war 100% preserved).
    - TC-8.2: corrupt/incompatible save rejection; automatic .bak fallback verified.
    - TC-8.3: HUD save button UI workflow and MainMenu load button UI verified end-to-end.

### [0.8.0] - 2026-10-12
#### Added
- Phase 7 Population Growth, Victory, Collapse & Summaries completed:
  - Deterministic immigration manager `scripts/economy/immigration_manager.gd` pacing arrivals (every 3 days at 06:00) with condition gating (housing capacity $>$ population, food $\ge 30$, stability $\ge 50\%$, morale $\ge 60\%$), generating unique citizen IDs and Vietnamese names.
  - Authoritative victory, crisis, and collapse manager `scripts/core/victory_manager.gd` enforcing continuous 5-day (120-hour) prosperity hold (population $\ge 30$, food $\ge 500$, treasury $\ge 1000$, stability $\ge 80\%$, morale $\ge 75\%$, technologies $\ge 3$) with immediate duration reset to 0 upon metric lapse.
  - Deterministic collapse failure triggers: Extinction (population $\le 0$), Town Hall Ruin ($> 72$ hours destroyed), and Prolonged Anarchy ($> 72$ hours at $0\%$ stability) generating structured failure summaries without deleting save data.
  - Legacy achievement reward system with double-spend protection (`claim_legacy_reward`).
  - In-Game HUD Victory modal dialog ("👑 CHIẾN THẮNG THỊNH VƯỢNG!"), Collapse modal dialog ("💀 VƯƠNG QUỐC SỤP ĐỔ!"), Crisis alert banner, and dynamic population display (`👥 Dân số: %d/%d`).
  - Automated headless test suite `scripts/test/test_victory_and_collapse.gd` (TC-7.1, TC-7.2, TC-7.3 passed).

#### Added
- Phase 6 Factions, Diplomacy, Trade & Abstract Battles completed:
  - Faction management subsystem `scripts/factions/faction_data.gd` and `scripts/factions/faction_manager.gd` tracking 2 rival kingdoms ("Cổ Thành Thiết Giáp", "Thương Hội Vân Đồn") and 1 neutral tribe ("Bản Làng Rừng Xanh") with continuous disposition (-100 to +100), stability, military power, treaties (Neutral, Peace, Non-Aggression, Alliance, War), diplomatic gift sending, and neutral tribe ascension mechanics.
  - Royal Trade Caravan simulation `scripts/trade/trade_caravan.gd` with deterministic seed arrivals (every 5 days), finite inventories, asymmetric buy/sell pricing (with diplomatic disposition discounts), atomic item transactions, and double-spending prevention.
  - Deterministic Battle Resolver `scripts/combat/battle_resolver.gd` modeling attacker/defender troops, equipment tier (1-3), morale, fortification level (0-3), terrain bonuses (chokepoints, high ground), casualty calculation, and plunder spoils (20% defender stock) satisfying GDD 10.4 without random outcome swings.
  - In-Game HUD Royal Diplomacy & Trade interface (`scenes/ui/hud.tscn` and `scripts/ui/hud.gd`) accessible via HUD button and shortcut `KEY_Y`.
  - Automated headless test suite `scripts/test/test_factions_and_battles.gd` (TC-6.1 and TC-6.2 passed).

#### Added
- Phase 5 Research, Exploration & Events completed:
  - Central technology tree `scripts/research/tech_tree.gd` with 4 branches (survival, production, military, mysticism) and 10 technologies with prerequisites and atomic resource deductions.
  - Royal Research Institute system `scripts/research/research_manager.gd` enforcing single active project constraint, atomic upfront cost deduction, 50% cancellation refund, pause safety, and global research bonuses (+500 storage capacity, +25% research speed).
  - 3-state Fog of War simulation `scripts/world/fog_of_war.gd` (UNEXPLORED, EXPLORED, VISIBLE) with diamond sight reveals.
  - Deterministic Points of Interest `scripts/world/poi_manager.gd` (Ancient Ruins, Abandoned Mines, Sacred Groves, Ancient Shrines) with single-claim persistent discovery rewards rejecting double-spending.
  - World events system `scripts/core/world_event_system.gd` with periodic positive/negative events and cooldown intervals.
  - Decoupled event router autoload `scripts/core/event_manager.gd` registered in `project.godot`.
  - In-Game HUD Royal Research Institute panel (`KEY_T`), Research button, and Event Banner.
  - Ancient Ruins pixel art prop `assets/props/prop_poi_ruins.png`.
  - Automated test suite `scripts/test/test_research_and_exploration.gd` (TC-5.1, TC-5.2, TC-5.3 passed).

### [0.5.0] - 2026-10-12
#### Added
- Phase 4 Working Logistics Loop & Basic Automation completed:
  - Local workplace output buffers `scripts/economy/workplace_manager.gd` (Farm: 50 food buffer, Woodcutter: 40 wood buffer) preventing instant teleportation of goods.
  - Physical hauling loop: haulers claim hauling jobs, travel to workplace access points, extract cargo, navigate to storehouses, and deposit goods into central stock.
  - Seasonal agriculture output modifiers ($1.2\times$ Summer, $0.5\times$ Winter, $1.0\times$ Spring/Autumn) scaling farm production.
  - Non-instant starvation escalation: when food depletes, "Nạn đói" state initiates; health decays gradually at 5%/day with 0 instant deaths, recovering naturally when fed.
  - Configurable priority automation rules with strict execution budget ($O(1)$ constant time) in `scripts/economy/automation_manager.gd` preventing performance death spirals.
  - In-game HUD citizen inspector displays live carried cargo.
  - Automated headless test suite `scripts/test/test_logistics.gd` (TC-4.1, TC-4.2, TC-4.3 passed).

### [0.4.0] - 2026-10-12
#### Added
- Phase 3 Citizens, Navigation & Real Jobs completed:
  - Discrete 2D A* grid pathfinder `scripts/navigation/grid_navigation.gd` operating on 64×64 simulation grid with obstacle avoidance.
  - Authoritative Job Manager `scripts/jobs/job_manager.gd` tracking workplace capacities and construction/production job lifecycles.
  - Citizen controller `scripts/entities/citizen_controller.gd` and scene `scenes/entities/citizen.tscn` with ground-contact foot pivot at (12, 30) for Y-sorting.
  - Instantiation of exactly 24 starter citizens with unique stable IDs and starter roles (5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle).
  - Hourly citizen need decay simulation (Hunger, Fatigue, Health, Morale).
  - Citizen inspection UI panel integrated into HUD (`scenes/ui/hud.tscn` and `scripts/ui/hud.gd`) displaying citizen stats, state, job, and path.
  - Automated headless test suite `scripts/test/test_citizens.gd` (TC-3.1 and TC-3.2 passed).

### [0.3.0] - 2026-10-12
#### Added
- Phase 2 Authoritative Economy & Building Systems completed:
  - Central data-driven economy configuration `scripts/economy/economy_config.gd` with 9 stable resource IDs and building blueprints.
  - Authoritative `scripts/economy/resource_manager.gd` singleton with atomic multi-resource cost reservation (`reserve_cost`), deduction (`commit_cost`), and cancellation (`release_cost`).
  - Storage capacity limits enforcement and daily food upkeep consumption tick ($0.8 \times 24 = 19.2 \approx 20$ Food/day).
  - Building placement validation `scripts/economy/building_system.gd` enforcing grid bounds, water prohibition, and occupancy tracking.
  - Interactive In-Game Build Menu and real-time ghost building placement preview.
  - Automated headless economy test suite `scripts/test/test_economy.gd` (TC-2.1 and TC-2.2 passed).
#### Added
- Phase 1 Vertical Slice & Visual-Validation Gate completed:
  - Coordinate decoupling utility `scripts/utils/iso_math.gd` with 2:1 dimetric isometric forward/inverse math.
  - Automated coordinate unit test `scripts/test/test_coordinates.gd` (TC-1.1 passed).
  - Authoritative simulation clock `scripts/core/time_manager.gd` with pause safety, speeds (0x–3x), and calendar.
  - Automated TimeManager unit test `scripts/test/test_time_manager.gd` (TC-1.4 passed).
  - Procedural pixel-art asset generator `scripts/tools/generate_pixel_assets.gd` generating 13 assets adhering strictly to `docs/ASSET_STYLE_GUIDE.md` and 27-color palette.
  - Deterministic procedural world generator `scripts/world/world_generator.gd` generating 64×64 simulation grid.
  - Automated world generator reproducibility test `scripts/test/test_world_gen.gd` (TC-1.2 passed).
  - Dedicated Visual-Validation Gate scene `scenes/test/visual_validation_test.tscn` demonstrating terrain, props, building with visible rooftop/facade, moving citizen, diamond cursor hover, and flawless Y-sorting.
  - In-Game HUD `scenes/ui/hud.tscn` with time controls, clock, resource ledger, and pause menu.
  - 64×64 Full World View `scenes/world/world_view.tscn` with starter buildings and 24 citizens.
  - Main Menu `scenes/ui/main_menu.tscn` with New World (seed, difficulty), Settings, and Quit.
  - Configured `run/main_scene` in `project.godot`.
#### Added
- Formalized comprehensive project specification suite:
  - `docs/SCOPE_DECISIONS.md` resolving all GDD design ambiguities and starter resource allocations.
  - `docs/GAME_RULES.md` specifying 2:1 dimetric isometric coordinate formulas, simulation tick schedules, needs decay rates, and victory/collapse conditions.
  - `docs/ARCHITECTURE.md` establishing strict separation between 64×64 logical simulation and presentation layers.
  - `docs/IMPLEMENTATION_PLAN.md` defining phased execution roadmap across 10 technical phases.
  - `docs/TEST_PLAN.md` establishing headless command-line and Godot MCP verification suites.
  - `docs/BACKLOG.md` detailing prioritized tasks and dependency chains.
  - `docs/KNOWN_ISSUES.md` recording technical diagnostic solutions.
- Added `docs/.gdignore` to cleanly isolate documentation from Godot's asset importer.
- Configured `MCPRuntime` autoload singleton in `project.godot`.
- Verified live Godot MCP bridge connection on port 6505.
