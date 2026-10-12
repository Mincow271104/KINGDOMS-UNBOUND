extends Node
## EventManager Autoload Singleton for KINGDOMS UNBOUND.
## Central decoupled event router for world events, discoveries, and alerts.

signal event_triggered(event_id: String, title: String, description: String, is_positive: bool, payload: Dictionary)
signal poi_discovered(poi_id: String, poi_name: String, cell: Vector2i)
signal poi_claimed(poi_id: String, poi_name: String, rewards: Dictionary)
signal tech_unlocked(tech_id: String, tech_name: String)

var _event_history: Array[Dictionary] = []

func trigger_event(
	event_id: String,
	title: String,
	description: String,
	is_positive: bool = true,
	payload: Dictionary = {}
) -> void:
	var entry := {
		"id": event_id,
		"title": title,
		"description": description,
		"is_positive": is_positive,
		"payload": payload,
		"timestamp": Time.get_ticks_msec()
	}
	_event_history.append(entry)
	event_triggered.emit(event_id, title, description, is_positive, payload)
	print("[EventManager] Event Triggered: %s - %s" % [title, description])

func notify_poi_discovered(poi_id: String, poi_name: String, cell: Vector2i) -> void:
	poi_discovered.emit(poi_id, poi_name, cell)
	print("[EventManager] POI Discovered: %s at %s" % [poi_name, cell])

func notify_poi_claimed(poi_id: String, poi_name: String, rewards: Dictionary) -> void:
	poi_claimed.emit(poi_id, poi_name, rewards)
	print("[EventManager] POI Claimed: %s. Rewards: %s" % [poi_name, rewards])

func notify_tech_unlocked(tech_id: String, tech_name: String) -> void:
	tech_unlocked.emit(tech_id, tech_name)
	print("[EventManager] Tech Unlocked: %s (%s)" % [tech_name, tech_id])

func get_recent_events(limit: int = 10) -> Array[Dictionary]:
	if _event_history.size() <= limit:
		return _event_history.duplicate()
	return _event_history.slice(_event_history.size() - limit)

func clear_history() -> void:
	_event_history.clear()
