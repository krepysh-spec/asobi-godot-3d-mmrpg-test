class_name AsobiEconomy
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func get_wallets() -> Dictionary:
	return await _client.http.get_request(_client, "/api/v1/wallets")

func get_history(currency: String, limit: int = 50) -> Dictionary:
	return await _client.http.get_request(
		_client, "/api/v1/wallets/%s/history" % currency, {"limit": str(limit)})

func get_store(currency: String = "") -> Dictionary:
	var query := {"currency": currency} if currency != "" else {}
	return await _client.http.get_request(_client, "/api/v1/store", query)

func purchase(listing_id: String) -> Dictionary:
	return await _client.http.post_request(
		_client, "/api/v1/store/purchase", {"listing_id": listing_id})
