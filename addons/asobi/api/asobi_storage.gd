class_name AsobiStorage
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func list_saves() -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/saves")

func get_save(slot: String) -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/saves/%s" % slot)

func put_save(slot: String, data: Dictionary, version: int = -1) -> Dictionary:
	var body := {"data": data}
	if version >= 0:
		body["version"] = version
	return await _client.http.put_request(_client, "/api/v1/saves/%s" % slot, body)

func list_storage(collection: String, limit: int = 50) -> Dictionary:
	return await _client.http.get_request(
		_client, "/api/v1/storage/%s" % collection, {"limit": str(limit)})

func get_storage(collection: String, key: String) -> Dictionary:
	return await _client.http.get_request(
		_client, "/api/v1/storage/%s/%s" % [collection, key])

func put_storage(collection: String, key: String, value: Dictionary,
		read_perm: String = "owner", write_perm: String = "owner") -> Dictionary:
	return await _client.http.put_request(
		_client, "/api/v1/storage/%s/%s" % [collection, key],
		{"value": value, "read_perm": read_perm, "write_perm": write_perm})

func delete_storage(collection: String, key: String) -> Dictionary:
	return await _client.http.delete_request(
		_client, "/api/v1/storage/%s/%s" % [collection, key])
