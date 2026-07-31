extends CharacterBody3D

## Units per second. A zone is 16 units, so this is roughly one zone crossed
## every 1.3 seconds.
@export var speed := 12.0
@export var jump_velocity := 5.0
## How fast the cube swings round to face the cursor. Framerate-independent.
@export var aim_speed := 18.0
@export var player_name := "Player":
	set(value):
		player_name = value
		if is_node_ready():
			name_label.text = value

@onready var name_label: Label3D = $NameLabel

func _ready() -> void:
	name_label.text = player_name

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	_aim_at_cursor(delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

## Face wherever the mouse is pointing on the ground. This is the same aim the
## shot uses, and it is the yaw net_world.gd reports, so other clients see the
## barrel swing with the cursor.
##
## The camera must not be a child that inherits this rotation, or turning would
## swing the view, which moves the cursor's ground point, which turns further.
## camera_zoom.gd detaches it for exactly that reason.
func _aim_at_cursor(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse := get_viewport().get_mouse_position()
	var ground: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(
		camera.project_ray_origin(mouse), camera.project_ray_normal(mouse),
	)
	if ground == null:
		return

	var to_cursor: Vector3 = ground - global_position
	to_cursor.y = 0.0
	if to_cursor.length_squared() < 0.04:
		return

	# -Z is forward, hence the negated components.
	var want := atan2(-to_cursor.x, -to_cursor.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-aim_speed * delta))
