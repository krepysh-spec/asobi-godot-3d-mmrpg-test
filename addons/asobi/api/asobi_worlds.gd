class_name AsobiWorlds
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func list_worlds(mode: String = "", has_capacity: String = "") -> Dictionary:
	var query := {}
	if mode != "":
		query["mode"] = mode
	if has_capacity != "":
		query["has_capacity"] = has_capacity
	return await _client.http.get_request(_client, "/api/v1/worlds", query)

func get_world(world_id: String) -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/worlds/%s" % world_id)

func create_world(mode: String) -> Dictionary:
	return await _client.http.post_request(_client, "/api/v1/worlds", {"mode": mode})
