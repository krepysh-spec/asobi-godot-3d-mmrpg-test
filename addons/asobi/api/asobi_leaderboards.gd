class_name AsobiLeaderboards
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func get_top(leaderboard_id: String, limit: int = 100) -> Dictionary:
	return await _client.http.get_request(
		_client, "/api/v1/leaderboards/%s" % leaderboard_id, {"limit": str(limit)})

func get_around_player(leaderboard_id: String, player_id: String, range_size: int = 5) -> Dictionary:
	return await _client.http.get_request(
		_client, "/api/v1/leaderboards/%s/around/%s" % [leaderboard_id, player_id],
		{"range": str(range_size)})

func get_around_self(leaderboard_id: String, range_size: int = 5) -> Dictionary:
	return await get_around_player(leaderboard_id, _client.player_id, range_size)

func submit_score(leaderboard_id: String, score: int, sub_score: int = 0) -> Dictionary:
	return await _client.http.post_request(
		_client, "/api/v1/leaderboards/%s" % leaderboard_id,
		{"score": score, "sub_score": sub_score})
