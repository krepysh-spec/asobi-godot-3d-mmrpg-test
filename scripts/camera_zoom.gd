extends Camera3D

## Follows the player and zooms with the mouse wheel.
##
## The camera keeps the framing it was placed with in the scene and only slides
## along that line, so the pitch never changes and the view keeps its shape at
## every distance.
##
## It follows the player's *position* only. Sitting in the scene as a child of
## the player it would also inherit the yaw, and since player.gd turns the cube
## to face the cursor, the view would swing with every aim -- which moves the
## cursor's ground point, which turns the cube further. `top_level` cuts the
## parent transform out and this script re-applies the position by hand.

## Multiplicative, so one notch of the wheel moves the camera by the same
## proportion whether it is close in or far out.
@export var step := 1.15
@export var min_distance := 3.0
@export var max_distance := 40.0
## Higher is snappier. Framerate-independent, see _process.
@export var smoothing := 12.0

var _axis := Vector3.BACK
var _distance := 0.0
var _target := 0.0
var _follow: Node3D

func _ready() -> void:
	_follow = get_parent() as Node3D

	# Read the framing while the transform is still the scene's local one.
	_distance = position.length()
	if is_zero_approx(_distance):
		# A camera sitting on the player has no line to zoom along. Fall back to
		# the framing player.tscn ships with instead of dividing by zero.
		position = Vector3(0.0, 6.0, 10.0)
		_distance = position.length()

	_axis = position / _distance
	_target = _distance

	# From here position and rotation are global. The rotation authored in the
	# scene is the pitch and carries over unchanged; the yaw is the point --
	# there is none, and the player's does not reach it.
	top_level = true
	_place()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_zoom_to(_target / step)
	elif event.is_action_pressed("camera_zoom_out"):
		_zoom_to(_target * step)

func _process(delta: float) -> void:
	if not is_equal_approx(_distance, _target):
		# exp() rather than a fixed lerp weight, so the glide takes the same
		# time whatever the framerate.
		_distance = lerpf(_distance, _target, 1.0 - exp(-smoothing * delta))
	_place()

func _place() -> void:
	if _follow == null:
		return
	global_position = _follow.global_position + _axis * _distance

func _zoom_to(distance: float) -> void:
	_target = clampf(distance, min_distance, max_distance)
