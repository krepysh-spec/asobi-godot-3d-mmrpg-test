class_name AsobiDM
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func send(recipient_id: String, content: String) -> Dictionary:
	return await _client.http.post_request(
		_client, "/api/v1/dm", {"recipient_id": recipient_id, "content": content})

func history(player_id: String, limit: int = 50) -> Dictionary:
	return await _client.http.get_request(
		_client, "/api/v1/dm/%s/history" % player_id, {"limit": str(limit)})
