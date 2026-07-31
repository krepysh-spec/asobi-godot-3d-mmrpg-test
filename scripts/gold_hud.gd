extends CanvasLayer

## Always-on readout of what the player is carrying.
##
## Separate from the debug overlay on purpose: that one is a developer tool
## behind F3, this is part of the game and never hides.

@export var net_path: NodePath

## Refreshes per second. Gold only changes when something is picked up, so this
## does not need frame rate.
@export var refresh_hz := 10.0

var _net: Node
var _accum := 0.0
var _shown := -1

@onready var label: Label = $Panel/Label

func _ready() -> void:
	if net_path != NodePath() and has_node(net_path):
		_net = get_node(net_path)
	_refresh()

func _process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0 / refresh_hz:
		return
	_accum = 0.0
	_refresh()

func _refresh() -> void:
	# Explicitly typed: _net is a plain Node, so the call is untyped and := has
	# nothing to infer from.
	var gold: int = _net.gold() if _net != null else 0
	if gold == _shown:
		return
	_shown = gold
	label.text = "Gold  %d" % gold
