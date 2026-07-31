class_name AsobiTournaments
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func list(status: String = "", limit: int = 0) -> Dictionary:
	var query := {}
	if status != "":
		query["status"] = status
	if limit > 0:
		query["limit"] = str(limit)
	return await _client.http.get_request(_client, "/api/v1/tournaments", query)

func get_tournament(tournament_id: String) -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/tournaments/%s" % tournament_id)

func join(tournament_id: String) -> Dictionary:
	return await _client.http.post_request(_client, "/api/v1/tournaments/%s/join" % tournament_id)
