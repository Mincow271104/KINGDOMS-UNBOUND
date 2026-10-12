class_name WorldEventSystem
extends RefCounted
## World Events System for KINGDOMS UNBOUND.
## Generates periodic positive/negative colony events with deterministic cooldowns and UI notifications.

const EVENTS: Array[Dictionary] = [
	{
		"id": "bountiful_harvest",
		"title": "Mùa Màng Bội Thu",
		"description": "Thời tiết thuận hòa, đồng ruộng tươi tốt. Nông trại tăng 50% sản lượng trong 2 ngày tiếp theo.",
		"is_positive": true,
		"effect": {"farm_modifier_bonus": 0.5, "bonus_food": 30}
	},
	{
		"id": "heatwave",
		"title": "Đợt Nắng Nóng Gay Gắt",
		"description": "Nhiệt độ oi bức khiến dân làng nhanh kiệt sức. Thể lực tiêu hao nhanh hơn và nguy cơ thiếu nước tăng cao.",
		"is_positive": false,
		"effect": {"fatigue_multiplier": 1.25}
	},
	{
		"id": "wandering_herbalist",
		"title": "Dược Sư Du Phương",
		"description": "Một đoàn y sĩ ghé thăm quảng trường định cư, chia sẻ 20 Thảo Dược và chăm sóc sức khỏe cho dân làng.",
		"is_positive": true,
		"effect": {"grant_resource": {EconomyConfig.RES_HERBS: 20}, "heal_citizens": 15.0}
	},
	{
		"id": "bandit_scouts",
		"title": "Dấu Vết Đạo Tặc",
		"description": "Lính tuần tra phát hiện toán cướp rừng rình rập ngoài rìa lãnh thổ. Tinh thần cư dân tạm thời giảm nhẹ.",
		"is_positive": false,
		"effect": {"morale_penalty": -8.0}
	},
	{
		"id": "merchant_tribute",
		"title": "Đoàn Buôn Triều Cống",
		"description": "Thương đoàn phương xa mượn đường an toàn qua vương quốc, đóng góp 50 Vàng vào kho bạc.",
		"is_positive": true,
		"effect": {"grant_resource": {EconomyConfig.RES_GOLD: 50}}
	}
]

var last_event_day: int = -99
var min_days_between_events: int = 4
var rng: RandomNumberGenerator

func _init(seed_val: int = 12345) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_val + 9999

## Checks whether a scheduled world event should trigger on a given day.
func check_and_trigger_event(
	current_day: int,
	resource_mgr: Object,
	event_mgr: Object
) -> Dictionary:
	if current_day - last_event_day < min_days_between_events:
		return {}
		
	# Trigger event
	var event_idx: int = rng.randi_range(0, EVENTS.size() - 1)
	var ev: Dictionary = EVENTS[event_idx]
	last_event_day = current_day
	
	# Apply instant effects if any
	var effect: Dictionary = ev.get("effect", {})
	if effect.has("grant_resource") and resource_mgr != null:
		var grants: Dictionary = effect["grant_resource"]
		for res_id in grants:
			var amt: int = grants[res_id]
			resource_mgr.call("add_resource", res_id, amt)
			
	if effect.has("bonus_food") and resource_mgr != null:
		resource_mgr.call("add_resource", EconomyConfig.RES_FOOD, effect["bonus_food"])
		
	# Dispatch to EventManager
	if event_mgr != null:
		event_mgr.call("trigger_event", ev["id"], ev["title"], ev["description"], ev["is_positive"], ev)
		
	return ev
