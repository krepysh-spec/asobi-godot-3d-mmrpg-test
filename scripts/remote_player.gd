extends Node3D

## Visual stand-in for another connected player.
##
## Positions arrive at the server tick rate and are already a few tens of
## milliseconds old when they land, so drawing them as-is leaves the cube
## visibly trailing its player. Instead the last known velocity is carried
## forward for a short window, which cancels most of that delay.

## How hard the cube is pulled toward where it should be. This is a rate, not a
## per-frame fraction: the pull is frame-rate independent.
@export var smoothing := 20.0

## Seconds of movement to predict past the newest update. Roughly one update
## interval is honest; more starts overshooting when a player stops or turns.
## Set to 0 to disable prediction and interpolate only.
@export var max_prediction := 0.1

var _target := Vector3.ZERO
var _target_yaw := 0.0
var _velocity := Vector3.ZERO
var _since_update := 0.0

@onready var name_label: Label3D = $NameLabel

func _ready() -> void:
	_target = position

func _process(delta: float) -> void:
	_since_update += delta

	var predicted := _target + _velocity * minf(_since_update, max_prediction)
	var t := 1.0 - exp(-smoothing * delta)

	position = position.lerp(predicted, t)
	rotation.y = lerp_angle(rotation.y, _target_yaw, t)

func apply_state(to: Vector3, yaw: float) -> void:
	if _since_update > 0.001:
		var measured := (to - _target) / _since_update
		# A dropped or delayed packet reads as a huge jump; ignore those rather
		# than firing the cube across the map.
		if measured.length() < 100.0:
			_velocity = _velocity.lerp(measured, 0.5)
		else:
			_velocity = Vector3.ZERO

	_target = to
	_target_yaw = yaw
	_since_update = 0.0

func teleport(to: Vector3, yaw: float) -> void:
	position = to
	rotation.y = yaw
	_target = to
	_target_yaw = yaw
	_velocity = Vector3.ZERO
	_since_update = 0.0

func set_display_name(value: String) -> void:
	name_label.text = value
