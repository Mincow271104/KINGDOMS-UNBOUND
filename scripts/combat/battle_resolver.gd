class_name BattleResolver
extends RefCounted
## Deterministic Abstract Battle Resolver for KINGDOMS UNBOUND.
## Conforms to GDD Section 10.4:
## Multi-factor combat model factoring troops, equipment, fortifications, morale, and terrain.
## Produces explainable casualty breakdowns, spoils, and diplomatic consequences.

class BattleReport:
	var victor: String # "attacker", "defender", "stalemate"
	var attacker_troops_initial: int
	var attacker_casualties: int
	var attacker_troops_remaining: int
	var defender_troops_initial: int
	var defender_casualties: int
	var defender_troops_remaining: int
	var plunder_spoils: Dictionary = {}
	var explanation: String = ""
	var details: Dictionary = {}

static func resolve_battle(
	attacker_force: Dictionary,
	defender_force: Dictionary,
	seed_val: int = 12345
) -> BattleReport:
	var report := BattleReport.new()
	
	# Attacker parameters
	var atk_troops: int = attacker_force.get("troops", 20)
	var atk_equip: int = attacker_force.get("equipment_tier", 1) # 1..3
	var atk_morale: float = attacker_force.get("morale", 70.0) # 0..100
	
	# Defender parameters
	var def_troops: int = defender_force.get("troops", 20)
	var def_equip: int = defender_force.get("equipment_tier", 1) # 1..3
	var def_morale: float = defender_force.get("morale", 70.0) # 0..100
	var def_fort: int = defender_force.get("fortification_level", 0) # 0..3
	var def_terrain: float = defender_force.get("terrain_multiplier", 1.0) # 1.0..1.3
	
	report.attacker_troops_initial = atk_troops
	report.defender_troops_initial = def_troops
	
	# Deterministic combat rating calculation
	var atk_equip_bonus := 1.0 + float(atk_equip - 1) * 0.25
	var atk_morale_factor := clampf(atk_morale / 100.0, 0.4, 1.2)
	var atk_combat_score := float(atk_troops) * atk_equip_bonus * atk_morale_factor
	
	var def_equip_bonus := 1.0 + float(def_equip - 1) * 0.25
	var def_morale_factor := clampf(def_morale / 100.0, 0.4, 1.2)
	var def_fort_bonus := 1.0 + float(def_fort) * 0.30
	var def_combat_score := float(def_troops) * def_equip_bonus * def_morale_factor * def_fort_bonus * def_terrain
	
	# Small deterministic variance (+-5%) based on seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var variance := 1.0 + rng.randf_range(-0.05, 0.05)
	var final_atk_score := atk_combat_score * variance
	var final_def_score := def_combat_score
	
	# Victory resolution
	var score_ratio := final_atk_score / maxf(final_def_score, 0.001)
	
	if score_ratio > 1.10:
		report.victor = "attacker"
		# Attacker wins: suffers lower casualties
		var atk_loss_rate := clampf(0.12 * (1.0 / score_ratio), 0.08, 0.25)
		var def_loss_rate := clampf(0.40 * score_ratio, 0.35, 0.70)
		report.attacker_casualties = maxi(1, int(round(atk_troops * atk_loss_rate)))
		report.defender_casualties = maxi(1, int(round(def_troops * def_loss_rate)))
		
		# Plunder spoils if defender has resources
		var def_res: Dictionary = defender_force.get("resources", {})
		for r_id in def_res:
			var plundered: int = int(round(def_res[r_id] * 0.20))
			if plundered > 0:
				report.plunder_spoils[r_id] = plundered
				
		report.explanation = "Phe Tấn Công giành chiến thắng áp đảo nhờ sức mạnh chiến đấu vượt trội (Điểm công: %.1f vs Điểm thủ: %.1f)." % [final_atk_score, final_def_score]
	elif score_ratio < 0.90:
		report.victor = "defender"
		# Defender wins: fortifications and terrain held the line
		var def_loss_rate := clampf(0.12 * score_ratio, 0.08, 0.25)
		var atk_loss_rate := clampf(0.45 * (1.0 / score_ratio), 0.35, 0.70)
		report.defender_casualties = maxi(1, int(round(def_troops * def_loss_rate)))
		report.attacker_casualties = maxi(1, int(round(atk_troops * atk_loss_rate)))
		report.explanation = "Phe Phòng Thủ bảo vệ thành công lãnh thổ nhờ phòng tuyến vững chắc và công sự phòng ngự (Điểm thủ: %.1f vs Điểm công: %.1f)." % [final_def_score, final_atk_score]
	else:
		report.victor = "stalemate"
		report.attacker_casualties = maxi(1, int(round(atk_troops * 0.25)))
		report.defender_casualties = maxi(1, int(round(def_troops * 0.25)))
		report.explanation = "Trận chiến bất phân thắng bại, cả hai bên đều chịu tổn thất tương đương (Tỷ lệ lực lượng tương đương: %.2f)." % score_ratio
		
	report.attacker_troops_remaining = maxi(0, atk_troops - report.attacker_casualties)
	report.defender_troops_remaining = maxi(0, def_troops - report.defender_casualties)
	
	report.details = {
		"attacker_combat_score": final_atk_score,
		"defender_combat_score": final_def_score,
		"fortification_bonus": def_fort_bonus,
		"terrain_bonus": def_terrain,
		"score_ratio": score_ratio
	}
	return report
