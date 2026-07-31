class_name AsobiChat
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func get_history(channel_id: String, limit: int = 50) -> Dictionary:
	return await _client.http.get_request(
		_client, "/api/v1/chat/%s/history" % channel_id, {"limit": str(limit)})
