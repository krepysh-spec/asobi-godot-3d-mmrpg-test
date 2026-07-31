class_name AsobiMatches
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func list(mode: String = "", status: String = "", limit: int = 0) -> Dictionary:
	var query := {}
	if mode != "":
		query["mode"] = mode
	if status != "":
		query["status"] = status
	if limit > 0:
		query["limit"] = str(limit)
	return await _client.http.get_request(_client, "/api/v1/matches", query)

# Live, joinable matches. `list` reads the finished-match record table; this
# enumerates running match processes. has_capacity is only sent when true —
# the backend filters on the literal string "true" and ignores anything else.
func live(mode: String = "", has_capacity: bool = false) -> Dictionary:
	var query := {}
	if mode != "":
		query["mode"] = mode
	if has_capacity:
		query["has_capacity"] = "true"
	return await _client.http.get_request(_client, "/api/v1/matches/live", query)

func get_match(match_id: String) -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/matches/%s" % match_id)
