class_name AsobiPlayers
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func get_player(player_id: String) -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/players/%s" % player_id)

func update(
	player_id: String, display_name: String = "",
	avatar_url: String = "", metadata: Dictionary = {}
) -> Dictionary:
	var body := {}
	if display_name != "":
		body["display_name"] = display_name
	if avatar_url != "":
		body["avatar_url"] = avatar_url
	if not metadata.is_empty():
		body["metadata"] = metadata
	return await _client.http.put_request(_client, "/api/v1/players/%s" % player_id, body)

func get_self() -> Dictionary:
	return await get_player(_client.player_id)
