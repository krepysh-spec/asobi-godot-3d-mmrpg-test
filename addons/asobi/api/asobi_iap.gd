class_name AsobiIAP
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func verify_apple(signed_transaction: String) -> Dictionary:
	var body := {"signed_transaction": signed_transaction}
	return await _client.http.post_request(_client, "/api/v1/iap/apple", body)

func verify_google(product_id: String, purchase_token: String) -> Dictionary:
	var body := {"product_id": product_id, "purchase_token": purchase_token}
	return await _client.http.post_request(_client, "/api/v1/iap/google", body)
