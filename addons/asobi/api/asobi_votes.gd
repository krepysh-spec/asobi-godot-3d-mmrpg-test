class_name AsobiVotes
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func list_for_match(match_id: String) -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/matches/%s/votes" % match_id)

func get_vote(vote_id: String) -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/votes/%s" % vote_id)
