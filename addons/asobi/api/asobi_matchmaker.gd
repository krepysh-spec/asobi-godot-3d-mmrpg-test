class_name AsobiMatchmaker
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func add(mode: String = "default", properties: Dictionary = {}, party: Array = []) -> Dictionary:
	var body := {"mode": mode}
	if not properties.is_empty():
		body["properties"] = properties
	if not party.is_empty():
		body["party"] = party
	return await _client.http.post_request(_client, "/api/v1/matchmaker", body)

func status(ticket_id: String) -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/matchmaker/%s" % ticket_id)

func cancel(ticket_id: String) -> Dictionary:
	return await _client.http.delete_request(_client, "/api/v1/matchmaker/%s" % ticket_id)
