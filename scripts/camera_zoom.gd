extends Camera3D

## Mouse-wheel zoom.
##
## The camera slides along the line it was placed on in the scene rather than
## being repositioned, so the pitch never changes and the view keeps its shape
## at every distance. Nothing here rotates: movement in player.gd is on world
## axes, and turning the camera would leave WASD pointing somewhere else.

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

func _ready() -> void:
	_distance = position.length()
	if is_zero_approx(_distance):
		# A camera sitting on the player has no line to zoom along. Fall back to
		# the framing player.tscn ships with instead of dividing by zero.
		position = Vector3(0.0, 6.0, 10.0)
		_distance = position.length()

	_axis = position / _distance
	_target = _distance

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_zoom_to(_target / step)
	elif event.is_action_pressed("camera_zoom_out"):
		_zoom_to(_target * step)

func _process(delta: float) -> void:
	if is_equal_approx(_distance, _target):
		return

	# exp() rather than a fixed lerp weight, so the glide takes the same time
	# whatever the framerate.
	_distance = lerpf(_distance, _target, 1.0 - exp(-smoothing * delta))
	position = _axis * _distance

func _zoom_to(distance: float) -> void:
	_target = clampf(distance, min_distance, max_distance)
