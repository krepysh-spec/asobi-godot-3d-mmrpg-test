extends Node3D

## Connects to the asobi world server, reports the local player's position and
## renders everyone else.
##
## Coordinate mapping (server is 2D, client is 3D):
##   server x -> Godot x
##   server y -> Godot z
##   Godot y is height, client-only; the server never sees it.
## No scale, no offset — the floor is placed to span 0..WORLD_SIZE so a server
## coordinate is a Godot coordinate.

const REMOTE_PLAYER := preload("res://scenes/remote_player.tscn")
const PROP := preload("res://scenes/prop.tscn")

const MODE := "spawns"

# Must match grid_size * zone_size in asobi/lua/world.lua.
const GRID_SIZE := 2000
const ZONE_SIZE := 16.0
const WORLD_SIZE := GRID_SIZE * ZONE_SIZE

const SEND_HZ := 15.0
const GROUND_Y := 0.75  # floor top (0.25) + half the 1x1x1 cube

# Must match view_radius in asobi/lua/world.lua.
const VIEW_RADIUS := 1

@export var player_path: NodePath

## Hide players further away than VIEW_RADIUS zones.
##
## This is cosmetic, not interest management. asobi 0.45/0.46 never re-homes a
## player between zones -- asobi_zone only transfers NPCs out of bounds -- so
## every player stays subscribed to the zone they spawned in and the server
## sends everyone to everyone. The culling below reproduces what the streaming
## would look like, but the data still crosses the wire and a modified client
## could draw it anyway.
##
## Turn off to see the raw server behaviour.
@export var cull_by_zone := true

var _player: Node3D
var _remotes: Dictionary = {}   # player_id -> Node3D
var _props: Dictionary = {}     # entity_id -> Node3D
var _states: Dictionary = {}    # entity_id -> merged state (u ops are partial)
var _my_id := ""
var _display_name := "Player"
var _seq := 0
var _send_accum := 0.0
var _joined := false
var _spawned := false
var _tick := 0
var _ticks_seen := 0

func _ready() -> void:
	_player = get_node(player_path)

	Asobi.host = _config("host", "ASOBI_HOST", "localhost")
	Asobi.port = int(_config("port", "ASOBI_PORT", "8080"))

	_display_name = _config("name", "ASOBI_NAME", "Player")
	_player.player_name = _display_name

	# The first world.tick after world.joined is the initial snapshot, so the
	# handlers have to exist before we join.
	Asobi.realtime.connected.connect(_on_connected)
	Asobi.realtime.world_joined.connect(_on_world_joined)
	Asobi.realtime.world_tick.connect(_on_world_tick)
	Asobi.realtime.world_event.connect(_on_world_event)
	Asobi.realtime.error_received.connect(_on_error)

	_sign_in()

func _process(delta: float) -> void:
	if not _spawned:
		return

	_player.position.x = clampf(_player.position.x, 0.0, WORLD_SIZE)
	_player.position.z = clampf(_player.position.z, 0.0, WORLD_SIZE)

	# Reported unconditionally, including while standing still: the server reaps
	# players whose seq stops advancing, so silence reads as a disconnect.
	var interval := 1.0 / SEND_HZ
	_send_accum += delta
	while _send_accum >= interval:
		_send_accum -= interval
		_send_move()

	_cull()

# Hides everything outside the player's own ring of zones, so leaving a zone
# stops drawing its contents. Re-evaluated every frame because the player moving
# changes what is in range just as much as an entity moving does.
func _cull() -> void:
	var here := zone_of(_player.position)

	for id in _remotes:
		var node: Node3D = _remotes[id]
		node.visible = not cull_by_zone or _in_view(here, _zone_from_state(id, node.position))

	for id in _props:
		var node: Node3D = _props[id]
		node.visible = not cull_by_zone or _in_view(here, _zone_from_state(id, node.position))

func _in_view(here: Vector2i, there: Vector2i) -> bool:
	return maxi(absi(there.x - here.x), absi(there.y - here.y)) <= VIEW_RADIUS

# Entities carry their zone, so trust that over re-deriving it from a rendered
# position that may still be interpolating toward the real one.
func _zone_from_state(id: String, fallback_position: Vector3) -> Vector2i:
	var state: Dictionary = _states.get(id, {})
	if state.has("cx") and state.has("cy"):
		return Vector2i(int(state["cx"]), int(state["cy"]))
	return zone_of(fallback_position)

func _exit_tree() -> void:
	if _joined:
		Asobi.realtime.world_leave()

func _sign_in() -> void:
	# Two clients on one machine share user://, so they need separate credential
	# files or both sign in as the same player and drive one cube.
	var opts := {}
	var device := _config("device", "ASOBI_DEVICE", "")
	if device != "":
		opts["path"] = device

	var resp: Dictionary = await Asobi.auth.guest_device(opts)
	if resp.has("error"):
		push_error("[net] guest sign-in failed: %s" % str(resp))
		return

	_my_id = Asobi.player_id
	Asobi.realtime.connect_to_server()

func _on_connected() -> void:
	Asobi.realtime.world_find_or_create(MODE)

func _on_world_joined(payload: Dictionary) -> void:
	_joined = true
	print("[net] joined world %s as %s" % [payload.get("world_id", "?"), _my_id])

func _on_world_event(event_name: String, payload: Dictionary) -> void:
	# find_or_create does not always answer with world.joined; when it answers
	# with a world we are not in yet, join it explicitly.
	if not _joined and payload.has("world_id"):
		Asobi.realtime.world_join(str(payload["world_id"]))

func _on_error(payload: Dictionary) -> void:
	push_error("[net] %s" % str(payload))

func _on_world_tick(payload: Dictionary) -> void:
	_tick = int(payload.get("tick", _tick))
	_ticks_seen += 1

	for raw in payload.get("updates", []):
		var update: Dictionary = raw
		var id := str(update.get("id", ""))
		if id == "":
			continue
		match str(update.get("op", "")):
			"a", "u":
				_apply(id, update)
			"r":
				_remove(id)

func _apply(id: String, update: Dictionary) -> void:
	# "u" carries changed fields only, so state is merged rather than replaced.
	var state: Dictionary = _states.get(id, {})
	for key in update:
		if key != "op" and key != "id":
			state[key] = update[key]
	_states[id] = state

	var kind := str(state.get("type", ""))
	if kind != "player":
		_apply_prop(id, kind, state)
		return

	if id == _my_id:
		_adopt_spawn(state)
		return

	var yaw := float(state.get("yaw", 0.0))
	var node: Node3D = _remotes.get(id)

	if node == null:
		node = REMOTE_PLAYER.instantiate()
		add_child(node)
		node.teleport(_to_godot(state), yaw)
		_remotes[id] = node
		print("[net] player joined: %s at %v (me at %v)" % [
			state.get("name", "?"), node.position, _player.position,
		])
	else:
		node.apply_state(_to_godot(state), yaw)

	node.set_display_name(str(state.get("name", "player")))

# Props never move, so they are placed once and only removed.
func _apply_prop(id: String, kind: String, state: Dictionary) -> void:
	if _props.has(id):
		return

	var node: Node3D = PROP.instantiate()
	add_child(node)
	node.apply_type(kind)
	var ground := node.position.y
	node.position = Vector3(
		float(state.get("x", 0.0)), ground, float(state.get("y", 0.0)),
	)
	_props[id] = node

func _remove(id: String) -> void:
	_states.erase(id)

	var node: Node3D = _remotes.get(id)
	if node != null:
		node.queue_free()
		_remotes.erase(id)
		print("[net] player left: %s" % id)
		return

	node = _props.get(id)
	if node != null:
		node.queue_free()
		_props.erase(id)

# Take the server-assigned spawn before reporting anything, otherwise the first
# input would overwrite it with wherever the scene happened to place the cube.
func _adopt_spawn(state: Dictionary) -> void:
	if _spawned:
		return
	_spawned = true
	_player.position = _to_godot(state)

func _send_move() -> void:
	_seq += 1
	Asobi.realtime.world_input({
		"kind": "move",
		"x": _player.position.x,
		"y": _player.position.z,
		"yaw": _player.rotation.y,
		"name": _display_name,
		"seq": _seq,
	})

## Which zone a world position falls in. Mirrors the server's own
## cx = floor(x / zone_size) so the numbers shown match the server's.
func zone_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / ZONE_SIZE), floori(point.z / ZONE_SIZE))

## Snapshot for the debug overlay.
func debug_info() -> Dictionary:
	var here := zone_of(_player.position)
	var others: Array = []

	for id in _remotes:
		var state: Dictionary = _states.get(id, {})
		var node: Node3D = _remotes[id]
		var zone := _zone_from_state(id, node.position)
		others.append({
			"name": str(state.get("name", "?")),
			"zone": zone,
			"rings": maxi(absi(zone.x - here.x), absi(zone.y - here.y)),
			"distance": _player.position.distance_to(node.position),
			"shown": node.visible,
		})

	others.sort_custom(func(a, b): return a["distance"] < b["distance"])

	var props_shown := 0
	for id in _props:
		if _props[id].visible:
			props_shown += 1

	return {
		"connected": _joined,
		"spawned": _spawned,
		"name": _display_name,
		"zone": here,
		"position": _player.position,
		"tick": _tick,
		"ticks_seen": _ticks_seen,
		"others": others,
		"props_shown": props_shown,
		"props_received": _props.size(),
	}

func _to_godot(state: Dictionary) -> Vector3:
	return Vector3(float(state.get("x", 0.0)), GROUND_Y, float(state.get("y", 0.0)))

# Per-instance settings. The editor's Run Instances dialog can pass launch
# arguments but not environment variables, so a --key=value argument wins over
# the environment; the environment still works when launching from a shell.
func _config(arg_key: String, env_key: String, fallback: String) -> String:
	var prefix := "--%s=" % arg_key
	for source in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg in source:
			if arg.begins_with(prefix):
				return arg.substr(prefix.length())

	var value := OS.get_environment(env_key)
	return value if value != "" else fallback
