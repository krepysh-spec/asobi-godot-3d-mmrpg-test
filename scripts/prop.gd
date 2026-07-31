extends Node3D

## A zone-owned entity: cube, ore or chest. Layout comes from the server and is
## a pure function of the zone coordinates, so every player in a zone sees the
## same props in the same places.

const STYLES := {
	"cube":  {"size": Vector3(1.0, 1.0, 1.0), "color": Color(0.58, 0.58, 0.62)},
	"ore":   {"size": Vector3(0.8, 0.8, 0.8), "color": Color(0.85, 0.68, 0.18)},
	"chest": {"size": Vector3(1.3, 0.8, 0.9), "color": Color(0.48, 0.29, 0.14)},
}

# Shared per type so a few hundred props cost three meshes, not a few hundred.
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func apply_type(kind: String) -> void:
	if not STYLES.has(kind):
		kind = "cube"

	if not _meshes.has(kind):
		var mesh := BoxMesh.new()
		mesh.size = STYLES[kind]["size"]
		_meshes[kind] = mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = STYLES[kind]["color"]
		_materials[kind] = material

	mesh_instance.mesh = _meshes[kind]
	mesh_instance.material_override = _materials[kind]
	position.y = STYLES[kind]["size"].y * 0.5 + 0.25  # rest on the floor top
