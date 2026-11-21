class_name RivalVillagerActorPool
extends RefCounted
## Phase 6 Fixed-Cap Actor Pool for RivalVillagerActor.
## Guarantees active + pooled SceneTree actor count never exceeds max_actors (default 48)
## and never constrains canonical SettlementVillagerContext population.

const RivalVillagerActorScript = preload("res://scripts/world/rival_villager_actor.gd")

const MAX_ACTIVE_ACTORS: int = 48

var max_actors: int = MAX_ACTIVE_ACTORS
var _pool_container: Node = null
var _free_actors: Array[Node2D] = []
var _active_by_key: Dictionary = {} # "<sid>:<vid>" -> RivalVillagerActor
var _total_created: int = 0
var pool_exhausted_count: int = 0

func _init(p_pool_container: Node = null, p_max_actors: int = MAX_ACTIVE_ACTORS) -> void:
	_pool_container = p_pool_container
	max_actors = maxi(1, p_max_actors)

func set_pool_container(p_pool_container: Node) -> void:
	_pool_container = p_pool_container
	if _pool_container != null and is_instance_valid(_pool_container):
		for actor in _free_actors:
			if actor != null and is_instance_valid(actor) and actor.get_parent() != _pool_container:
				if actor.get_parent() != null:
					actor.get_parent().remove_child(actor)
				_pool_container.add_child(actor)

func get_active_count() -> int:
	return _active_by_key.size()

func get_free_count() -> int:
	return _free_actors.size()

func get_total_allocated() -> int:
	return _active_by_key.size() + _free_actors.size()

func has_active_actor(settlement_id: String, villager_id: String) -> bool:
	return _active_by_key.has("%s:%s" % [settlement_id, villager_id])

func get_active_actor(settlement_id: String, villager_id: String) -> Node2D:
	return _active_by_key.get("%s:%s" % [settlement_id, villager_id], null)

func get_all_active_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _active_by_key.keys():
		keys.append(String(k))
	return keys

func acquire(
	settlement_id: String,
	villager_id: String,
	faction_id: String = "",
	role: String = "",
	target_parent: Node = null
) -> Node2D:
	if settlement_id.is_empty() or villager_id.is_empty():
		return null
	var key := "%s:%s" % [settlement_id, villager_id]
	if _active_by_key.has(key):
		return _active_by_key[key]

	if _active_by_key.size() >= max_actors:
		pool_exhausted_count += 1
		return null

	var actor: Node2D = null
	if not _free_actors.is_empty():
		actor = _free_actors.pop_back()
	elif get_total_allocated() < max_actors:
		actor = RivalVillagerActorScript.new()
		_total_created += 1
	else:
		pool_exhausted_count += 1
		return null

	actor.bind_villager(settlement_id, villager_id, faction_id, role)
	var parent_node: Node = target_parent if (target_parent != null and is_instance_valid(target_parent)) else _pool_container
	if parent_node != null and is_instance_valid(parent_node):
		if actor.get_parent() != parent_node:
			if actor.get_parent() != null:
				actor.get_parent().remove_child(actor)
			parent_node.add_child(actor)

	_active_by_key[key] = actor
	return actor

func release(settlement_id: String, villager_id: String) -> bool:
	var key := "%s:%s" % [settlement_id, villager_id]
	if not _active_by_key.has(key):
		return false
	var actor: Node2D = _active_by_key[key]
	_active_by_key.erase(key)
	if actor != null and is_instance_valid(actor):
		actor.release_binding()
		if _pool_container != null and is_instance_valid(_pool_container):
			if actor.get_parent() != _pool_container:
				if actor.get_parent() != null:
					actor.get_parent().remove_child(actor)
				_pool_container.add_child(actor)
		elif actor.get_parent() != null:
			actor.get_parent().remove_child(actor)
		_free_actors.append(actor)
	return true

func release_settlement(settlement_id: String) -> int:
	var released: int = 0
	var to_release: Array[String] = []
	for key in _active_by_key.keys():
		var actor: Node2D = _active_by_key[key]
		if actor != null and actor.bound_settlement_id == settlement_id:
			to_release.append(String(key))
	for k in to_release:
		var parts: PackedStringArray = k.split(":", false, 1)
		if parts.size() == 2 and release(parts[0], parts[1]):
			released += 1
	return released

func release_all() -> void:
	for k in get_all_active_keys():
		var parts: PackedStringArray = k.split(":", false, 1)
		if parts.size() == 2:
			release(parts[0], parts[1])

func dispose_all() -> void:
	release_all()
	for actor in _free_actors:
		if actor != null and is_instance_valid(actor):
			if actor.get_parent() != null:
				actor.get_parent().remove_child(actor)
			actor.queue_free()
	_free_actors.clear()
