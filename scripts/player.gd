extends CharacterBody3D

## Units per second. A zone is 16 units, so this is roughly one zone crossed
## every 1.3 seconds.
@export var speed := 12.0
@export var jump_velocity := 5.0
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

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
