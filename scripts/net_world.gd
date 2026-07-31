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

# Must match SHOT_RANGE in asobi/lua/world.lua, which is the one that counts.
const SHOT_RANGE := 30.0
const SHOT_COOLDOWN := 0.25
# Must match PROP_LAYER in scripts/prop.gd.
const PROP_LAYER := 2
const TRACER_SECONDS := 0.06

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
var _shot_cooldown := 0.0
var _tracer_material: StandardMaterial3D

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

	_shot_cooldown = maxf(_shot_cooldown - delta, 0.0)
	if Input.is_action_pressed("shoot") and _shot_cooldown <= 0.0:
		_shoot()

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
	# Read before the merge: a shot is announced by shot_n going up, and after
	# merging there is nothing left to compare against.
	var seen_shots := int(state.get("shot_n", 0))
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

	# Somebody else fired. The shot rides on their entity rather than arriving as
	# its own message, so this is the only place it can be noticed.
	var shots := int(state.get("shot_n", 0))
	if shots > seen_shots and _in_view(zone_of(_player.position), _zone_from_state(id, node.position)):
		_tracer(node.position, Vector3(
			float(state.get("shot_x", 0.0)), node.position.y, float(state.get("shot_y", 0.0)),
		))

# Props never move, so position is set once. Health does change: a shot arrives
# as a partial update, and the node is re-read rather than rebuilt.
func _apply_prop(id: String, kind: String, state: Dictionary) -> void:
	var node: Node3D = _props.get(id)

	if node == null:
		node = PROP.instantiate()
		add_child(node)
		node.apply_type(kind)
		# The ray finds the body; the body has to be able to name the entity the
		# server knows it as.
		node.set_meta("entity_id", id)
		var ground := node.position.y
		node.position = Vector3(
			float(state.get("x", 0.0)), ground, float(state.get("y", 0.0)),
		)
		_props[id] = node

	if state.has("hp"):
		node.set_health(float(state["hp"]), float(state.get("hp_max", state["hp"])))
	elif state.has("amount"):
		node.set_amount(int(state["amount"]))

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

# The player never turns -- movement is on world axes and rotation.y stays 0 --
# so shots are aimed with the mouse rather than with the body. The ray looks at
# the prop layer only, which keeps the ground from swallowing a shot.
#
# The client picks the target and the server decides whether the shot counts, so
# a hit here is a request, not a result: the prop shrinks or vanishes when the
# next tick says so, never because this function fired.
func _shoot() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)

	var target_id := ""
	var point := Vector3.ZERO

	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 500.0, PROP_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		# A miss still has to land somewhere, or there is no shot for anyone to
		# see. Fire at the ground under the cursor.
		var ground: Variant = Plane(Vector3.UP, _player.position.y).intersects_ray(from, direction)
		if ground == null:
			return
		point = ground
	else:
		point = hit["position"]
		target_id = str(hit["collider"].get_parent().get_meta("entity_id", ""))

	# Out of range the shot still happens, it just falls short -- and hits
	# nothing. The server clamps the same way; this is only so the local tracer
	# matches what everyone else will be shown.
	var offset := point - _player.position
	if offset.length() > SHOT_RANGE:
		point = _player.position + offset.normalized() * SHOT_RANGE
		target_id = ""

	_shot_cooldown = SHOT_COOLDOWN
	_tracer(_player.position, point)

	var payload := {"kind": "shoot", "x": point.x, "y": point.z}
	if target_id != "":
		payload["target"] = target_id
	Asobi.realtime.world_input(payload)

func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return

	if _tracer_material == null:
		_tracer_material = StandardMaterial3D.new()
		_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_material.albedo_color = Color(1.0, 0.85, 0.4)

	var beam := BoxMesh.new()
	beam.size = Vector3(0.05, 0.05, length)

	var node := MeshInstance3D.new()
	node.mesh = beam
	node.material_override = _tracer_material
	add_child(node)
	node.global_position = (from + to) * 0.5

	# look_at cannot use an up vector parallel to the aim, which happens when
	# shooting something directly below.
	var aim := (to - from).normalized()
	node.look_at(to, Vector3.RIGHT if absf(aim.dot(Vector3.UP)) > 0.99 else Vector3.UP)

	get_tree().create_timer(TRACER_SECONDS).timeout.connect(node.queue_free)

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

## Gold picked up so far, as the server counts it. It rides on our own player
## entity, so it survives nothing: a reconnect is a new entity and a fresh purse.
func gold() -> int:
	return int(_states.get(_my_id, {}).get("gold", 0))

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
