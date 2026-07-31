class_name AsobiDevice
extends RefCounted

# Opt-in guest device-credential helper.
#
# Guest sign-in needs a stable {device_id, device_secret} that the game
# generates once, persists, and re-presents on every launch (same pair resumes
# the same player). This helper does that dance so a game doesn't hand-roll
# base64 + persistence + the >= 32-byte rule. Entirely optional: pass your own
# values to AsobiAuth.guest(...) if you want your own storage or key source.
#
# device_id:     any stable, per-install id (here: base64 of 16 random bytes).
# device_secret: standard base64 of 32 random bytes. The server requires this
#                exact shape - a value that base64-decodes to fewer than 32
#                bytes is rejected as weak_device_secret.
#
# Storage and RNG are swappable through the opts Dictionary so tests can inject
# an in-memory store and a deterministic byte source:
#   opts.random_bytes : Callable(int) -> PackedByteArray (default: Crypto CSPRNG)
#   opts.device_id    : String, fixes the id explicitly instead of generating it
#   opts.path         : String, user:// save path (default user://asobi_device.json)
#   opts.store        : object exposing load_creds()/save_creds(Dictionary)/
#                       clear_creds() - overrides opts.path entirely

const _DEFAULT_PATH := "user://asobi_device.json"


class _FileStore:
	extends RefCounted

	var _path: String

	func _init(path: String) -> void:
		_path = path

	func load_creds() -> Dictionary:
		if not FileAccess.file_exists(_path):
			return {}
		var file := FileAccess.open(_path, FileAccess.READ)
		if file == null:
			return {}
		var text := file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(text)
		return parsed if parsed is Dictionary else {}

	func save_creds(creds: Dictionary) -> bool:
		var file := FileAccess.open(_path, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(JSON.stringify(creds))
		file.close()
		return true

	func clear_creds() -> void:
		if FileAccess.file_exists(_path):
			DirAccess.remove_absolute(_path)


static func _random_bytes(opts: Dictionary, count: int) -> PackedByteArray:
	var rng: Callable = opts.get("random_bytes", Callable())
	if rng.is_valid():
		return rng.call(count)
	return Crypto.new().generate_random_bytes(count)


# Generate a fresh {device_id, device_secret} pair. opts.random_bytes(n) may
# supply bytes from your own source; opts.device_id fixes the id explicitly.
static func generate(opts: Dictionary = {}) -> Dictionary:
	var secret_bytes := _random_bytes(opts, 32)
	# Fail loud here rather than as an opaque server weak_device_secret 4xx if a
	# custom source under-delivers: the secret must decode to >= 32 bytes. A bare
	# assert() is stripped from release/exported builds, so a runtime check is
	# required - otherwise a bad injected source silently yields a short secret in
	# production. Return an {error} dict, which load_or_create/guest_device
	# propagate the same way as any other auth error.
	if secret_bytes.size() < 32:
		push_error(
			"AsobiDevice: random_bytes(32) returned %d bytes; need >= 32" % secret_bytes.size()
		)
		return {"error": "weak_device_secret"}
	secret_bytes = secret_bytes.slice(0, 32)

	var device_id: String = opts.get("device_id", "")
	if device_id == "":
		device_id = Marshalls.raw_to_base64(_random_bytes(opts, 16))

	return {
		"device_id": device_id,
		"device_secret": Marshalls.raw_to_base64(secret_bytes),
	}


static func _store(opts: Dictionary) -> Object:
	if opts.has("store"):
		return opts["store"]
	return _FileStore.new(opts.get("path", _DEFAULT_PATH))


static func _valid(creds: Dictionary) -> bool:
	return (
		creds.get("device_id", "") is String
		and creds.get("device_id", "") != ""
		and creds.get("device_secret", "") is String
		and creds.get("device_secret", "") != ""
	)


# Load the persisted pair, or generate + persist one on first run. Returns a
# {device_id, device_secret} Dictionary.
static func load_or_create(opts: Dictionary = {}) -> Dictionary:
	var store := _store(opts)
	var stored: Dictionary = store.load_creds()
	if _valid(stored):
		return {"device_id": stored["device_id"], "device_secret": stored["device_secret"]}

	var creds := generate(opts)
	if creds.has("error"):
		return creds
	# Best-effort: if the save fails (full disk, sandbox), the caller still gets
	# a usable pair for this session, but warn - a lost write means a different
	# guest next launch.
	if store.save_creds(creds) == false:
		push_warning("[asobi] could not persist guest device credentials; a new guest may be created next launch")
	return creds


# Erase the stored credentials so the next load_or_create / guest_device mints a
# brand-new guest (created = true). Use for "switch account", "play as someone
# else", or a local "forget me" / delete-my-data action. This is local-only: it
# does not delete the server account (pair it with logout to end the session, or
# upgrade_guest first if the player wants to keep it). Pass the same path/store
# opts you signed in with.
static func clear(opts: Dictionary = {}) -> void:
	_store(opts).clear_creds()
