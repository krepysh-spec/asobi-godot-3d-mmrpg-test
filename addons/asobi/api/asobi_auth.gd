class_name AsobiAuth
extends RefCounted

var _client: AsobiClient

func _init(client: AsobiClient) -> void:
	_client = client

func register(username: String, password: String, display_name: String = "") -> Dictionary:
	var body := {
		"username": username,
		"password": password,
		"display_name": display_name if display_name != "" else username
	}
	var resp: Dictionary = await _client.http.post_request(_client, "/api/v1/auth/register", body)
	if not resp.has("error"):
		_store_tokens(resp)
	return resp

func login(username: String, password: String) -> Dictionary:
	var body := {"username": username, "password": password}
	var resp: Dictionary = await _client.http.post_request(_client, "/api/v1/auth/login", body)
	if not resp.has("error"):
		_store_tokens(resp)
	return resp

func oauth(provider: String, token: String) -> Dictionary:
	var body := {"provider": provider, "token": token}
	var resp: Dictionary = await _client.http.post_request(_client, "/api/v1/auth/oauth", body)
	if not resp.has("error"):
		_store_tokens(resp)
	return resp

func guest(device_id: String, device_secret: String) -> Dictionary:
	var body := {"device_id": device_id, "device_secret": device_secret}
	var resp: Dictionary = await _client.http.post_request(_client, "/api/v1/auth/guest", body)
	if not resp.has("error"):
		_store_tokens(resp)
	return resp

# Opt-in convenience: load (or generate + persist) a device credential pair and
# sign in as a guest in one call. Equivalent to calling guest(...) with a
# {device_id, device_secret} you manage yourself. opts is forwarded to
# AsobiDevice.load_or_create (path/store/random_bytes/device_id overrides).
func guest_device(opts: Dictionary = {}) -> Dictionary:
	var creds := AsobiDevice.load_or_create(opts)
	if creds.has("error"):
		return creds
	return await guest(creds["device_id"], creds["device_secret"])

func upgrade_guest(username: String, password: String) -> Dictionary:
	var body := {"username": username, "password": password}
	var resp: Dictionary = await _client.http.post_request(_client, "/api/v1/auth/guest/upgrade", body)
	if not resp.has("error"):
		_store_tokens(resp)
	return resp

func link_provider(provider: String, token: String) -> Dictionary:
	var body := {"provider": provider, "token": token}
	return await _client.http.post_request(_client, "/api/v1/auth/link", body)

func unlink_provider(provider: String) -> Dictionary:
	return await _client.http.delete_request(_client, "/api/v1/auth/unlink", {}, {"provider": provider})

func refresh() -> Dictionary:
	var body := {"refresh_token": _client.refresh_token}
	var resp: Dictionary = await _client.http.post_request(_client, "/api/v1/auth/refresh", body)
	if not resp.has("error"):
		_client.access_token = resp.get("access_token", "")
		_client.refresh_token = resp.get("refresh_token", "")
		_client.save_refresh_token()
		if _client.realtime != null:
			_client.realtime.reauthenticate()
	return resp

func logout() -> Dictionary:
	var resp := {}
	if _client.refresh_token != "" or _client.access_token != "":
		resp = await _client.http.post_request(_client, "/api/v1/auth/logout", {"refresh_token": _client.refresh_token})
	_client.access_token = ""
	_client.player_id = ""
	_client.clear_persisted_token()
	return resp

func _store_tokens(resp: Dictionary) -> void:
	_client.access_token = resp.get("access_token", "")
	_client.refresh_token = resp.get("refresh_token", "")
	_client.player_id = resp.get("player_id", "")
	_client.save_refresh_token()
