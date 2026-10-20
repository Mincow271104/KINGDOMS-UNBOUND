class_name FactionData
extends RefCounted
## Faction Data Model for KINGDOMS UNBOUND.
## Conforms to GDD Section 10.1 & 10.2:
## Manages faction ID, name, military strength, stability, opinion, and diplomatic pacts.

enum Disposition {
	HOSTILE = 0,
	NEUTRAL = 1,
	FRIENDLY = 2,
	ALLIED = 3
}

var id: String
var name: String
var type: String # "player", "rival_military", "rival_merchant", "neutral_tribe"
var disposition: int = Disposition.NEUTRAL
var opinion: float = 0.0 # -100.0 to +100.0
var military_power: float = 50.0
var stability: float = 70.0 # 0.0 to 100.0
var is_at_war: bool = false
var has_nap: bool = false # Non-Aggression Pact
var has_alliance: bool = false
var resources: Dictionary = {}
var population: int = 40

func _init(
	p_id: String = "",
	p_name: String = "",
	p_type: String = "neutral_tribe",
	p_disp: int = Disposition.NEUTRAL,
	p_opinion: float = 0.0,
	p_mil: float = 50.0
) -> void:
	id = p_id
	name = p_name
	type = p_type
	disposition = p_disp
	opinion = p_opinion
	military_power = p_mil

func change_opinion(delta: float) -> void:
	opinion = clampf(opinion + delta, -100.0, 100.0)
	_update_disposition_from_opinion()

func recalculate_disposition() -> void:
	_update_disposition_from_opinion()

func _update_disposition_from_opinion() -> void:
	if is_at_war:
		disposition = Disposition.HOSTILE
		return
		
	if opinion <= -40.0:
		disposition = Disposition.HOSTILE
	elif opinion < 25.0:
		disposition = Disposition.NEUTRAL
	elif opinion < 75.0:
		disposition = Disposition.FRIENDLY
	else:
		disposition = Disposition.ALLIED

func declare_war() -> void:
	is_at_war = true
	has_nap = false
	has_alliance = false
	disposition = Disposition.HOSTILE
	change_opinion(-50.0)

func sign_peace() -> void:
	is_at_war = false
	change_opinion(20.0)

func sign_nap() -> bool:
	if is_at_war or opinion < 0.0:
		return false
	has_nap = true
	change_opinion(15.0)
	return true

func sign_alliance() -> bool:
	if is_at_war or opinion < 60.0:
		return false
	has_alliance = true
	has_nap = true
	disposition = Disposition.ALLIED
	change_opinion(25.0)
	return true

func get_disposition_name() -> String:
	if is_at_war:
		return "Chiến Tranh (Hostile)"
	match disposition:
		Disposition.HOSTILE: return "Thù Địch (Hostile)"
		Disposition.NEUTRAL: return "Trung Lập (Neutral)"
		Disposition.FRIENDLY: return "Hữu Hảo (Friendly)"
		Disposition.ALLIED: return "Đồng Minh (Allied)"
		_: return "Không xác định"
