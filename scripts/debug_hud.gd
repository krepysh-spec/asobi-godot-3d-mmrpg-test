extends CanvasLayer

## Top-left overlay for watching zone streaming.
##
## The interesting column is `rings`: how many zones away another player is.
## With view_radius = 1 on the server, anyone at rings >= 2 should not be
## visible at all -- if they still are, the server is not re-homing players
## between zones and everyone is stuck in the zone they spawned in.

@export var net_path: NodePath
@export var floor_path: NodePath

## Refreshes per second. The overlay does not need to run at frame rate.
@export var refresh_hz := 10.0

var _net: Node
var _floor: Node
var _accum := 0.0

@onready var label: Label = $Panel/Label

func _ready() -> void:
	if net_path != NodePath() and has_node(net_path):
		_net = get_node(net_path)
	if floor_path != NodePath() and has_node(floor_path):
		_floor = get_node(floor_path)
	_refresh()

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < 1.0 / refresh_hz:
		return
	_accum = 0.0
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			visible = not visible

func _refresh() -> void:
	if _net == null:
		label.text = "no NetWorld"
		return

	var info: Dictionary = _net.debug_info()
	var zone: Vector2i = info["zone"]
	var pos: Vector3 = info["position"]

	var lines: Array[String] = []

	var status := "joined" if info["connected"] else "connecting…"
	if info["connected"] and not info["spawned"]:
		status = "awaiting spawn"
	lines.append("%s — %s" % [info["name"], status])

	lines.append("zone     %d, %d" % [zone.x, zone.y])
	lines.append("pos      %.1f, %.1f" % [pos.x, pos.z])
	lines.append("tick     %d  (%d received)" % [info["tick"], info["ticks_seen"]])

	if _floor != null:
		lines.append("tiles    %d loaded" % _floor.loaded_tiles())

	lines.append("props    %d shown / %d received" % [
		info["props_shown"], info["props_received"],
	])

	var others: Array = info["others"]
	var shown := 0
	for other in others:
		if other["shown"]:
			shown += 1

	lines.append("")
	lines.append("players  %d shown / %d received" % [shown, others.size()])

	for other in others:
		var other_zone: Vector2i = other["zone"]
		lines.append("  %s %-9s z %d,%d  ring %d  %.0fu" % [
			"•" if other["shown"] else "×",
			other["name"],
			other_zone.x, other_zone.y,
			other["rings"],
			other["distance"],
		])

	label.text = "\n".join(lines)
