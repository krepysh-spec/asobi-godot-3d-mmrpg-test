extends Node3D

## A zone-owned entity: cube, ore or chest. Layout comes from the server and is
## a pure function of the zone coordinates, so every player in a zone sees the
## same props in the same places.
##
## Health lives on the server too. This node only draws it: a damaged prop
## shrinks, and it disappears when the server stops sending it, not when the
## client thinks it should.

## Props sit on their own physics layer. The shooting ray in net_world.gd looks
## at that layer only, so shots are never swallowed by the ground -- and since
## nothing masks the layer, props stay walk-through. Add layer 2 to the player's
## collision mask to make them solid.
const PROP_LAYER := 2

## How small a prop gets at a sliver of health. Not zero: it has to stay big
## enough to aim at right up to the last shot.
const MIN_SCALE := 0.55

const STYLES := {
	"cube":  {"size": Vector3(1.0, 1.0, 1.0), "color": Color(0.58, 0.58, 0.62)},
	"ore":   {"size": Vector3(0.8, 0.8, 0.8), "color": Color(0.85, 0.68, 0.18)},
	"chest": {"size": Vector3(1.3, 0.8, 0.9), "color": Color(0.48, 0.29, 0.14)},
	"gold":  {"size": Vector3(0.4, 0.25, 0.4), "color": Color(0.96, 0.79, 0.22)},
}

## Dropped gold is walked over, not shot, so it stays off the layer the
## shooting ray looks at. The server refuses to damage it either way.
const NOT_SHOOTABLE := ["gold"]

# Shared per type so a few hundred props cost three meshes, not a few hundred.
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _shapes: Dictionary = {}

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var body: StaticBody3D = $Body
@onready var collision: CollisionShape3D = $Body/CollisionShape3D
@onready var health_label: Label3D = $HealthLabel

var _size := Vector3.ONE

func apply_type(kind: String) -> void:
	if not STYLES.has(kind):
		kind = "cube"

	_size = STYLES[kind]["size"]

	if not _meshes.has(kind):
		var mesh := BoxMesh.new()
		mesh.size = _size
		_meshes[kind] = mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = STYLES[kind]["color"]
		_materials[kind] = material

		var shape := BoxShape3D.new()
		shape.size = _size
		_shapes[kind] = shape

	mesh_instance.mesh = _meshes[kind]
	mesh_instance.material_override = _materials[kind]

	# Deliberately not scaled with the mesh: the hitbox stays full size so a
	# nearly-dead prop is no harder to finish off than a fresh one.
	collision.shape = _shapes[kind]
	body.collision_layer = 0 if kind in NOT_SHOOTABLE else PROP_LAYER
	body.collision_mask = 0

	position.y = _size.y * 0.5 + 0.25  # rest on the floor top
	# Above the full-size box, so the number does not sink as the prop shrinks.
	health_label.position.y = _size.y * 0.5 + 0.35

## Damage feedback. hp and hp_max come straight from the server's entity state.
func set_health(hp: float, hp_max: float) -> void:
	var fraction := clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)
	var factor := lerpf(MIN_SCALE, 1.0, fraction)

	mesh_instance.scale = Vector3.ONE * factor
	# Shrinking about the box centre would leave the prop hovering, so drop it
	# by what the shrink took off the bottom half.
	mesh_instance.position.y = -_size.y * 0.5 * (1.0 - factor)

	health_label.text = "%d/%d" % [roundi(hp), roundi(hp_max)]
	# Green at full, red on the last hit, so damage reads at a glance.
	health_label.modulate = Color(0.95, 0.35, 0.3).lerp(Color(0.55, 0.9, 0.5), fraction)

## What a pile of dropped gold is worth. Same label, different meaning: gold has
## no health to show.
func set_amount(amount: int) -> void:
	health_label.text = str(amount)
	health_label.modulate = Color(0.98, 0.86, 0.35)
