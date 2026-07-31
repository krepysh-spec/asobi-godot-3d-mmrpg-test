@tool
extends Node3D

## Generates the world floor as a grid of separate section nodes,
## so culling and physics work per-section instead of on one huge mesh.

@export var map_size := 1000.0:
	set(value):
		map_size = value
		_rebuild()

@export var section_size := 50.0:
	set(value):
		section_size = maxf(value, 1.0)
		_rebuild()

@export var thickness := 0.5:
	set(value):
		thickness = maxf(value, 0.01)
		_rebuild()

@export var color_a := Color(0.35, 0.45, 0.35):
	set(value):
		color_a = value
		_rebuild()

@export var color_b := Color(0.30, 0.40, 0.30):
	set(value):
		color_b = value
		_rebuild()

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_node_ready():
		return

	for child in get_children():
		child.free()

	var count := int(ceil(map_size / section_size))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(section_size, thickness, section_size)

	var shape := BoxShape3D.new()
	shape.size = mesh.size

	var mat_a := StandardMaterial3D.new()
	mat_a.albedo_color = color_a
	var mat_b := StandardMaterial3D.new()
	mat_b.albedo_color = color_b

	var origin := -map_size * 0.5 + section_size * 0.5

	for x in count:
		for z in count:
			var section := StaticBody3D.new()
			section.name = "Section_%d_%d" % [x, z]
			section.position = Vector3(
				origin + x * section_size,
				0.0,
				origin + z * section_size,
			)
			add_child(section)

			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = mesh
			mesh_instance.material_override = mat_b if (x + z) % 2 else mat_a
			section.add_child(mesh_instance)

			var collision := CollisionShape3D.new()
			collision.shape = shape
			section.add_child(collision)

			if Engine.is_editor_hint():
				var scene_root := get_tree().edited_scene_root
				section.owner = scene_root
				mesh_instance.owner = scene_root
				collision.owner = scene_root
