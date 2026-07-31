@tool
extends Node3D

## Streams the floor as a window of tiles around the player.
##
## One tile is one server zone, so zone_size and grid_size must match the
## values in asobi/lua/world.lua. The full grid is far too large to build --
## only the tiles within view_tiles of the player exist at any moment, and they
## are created and freed as the player crosses tile boundaries.

## Units per tile side. Must match zone_size on the server.
@export var zone_size := 16.0:
	set(value):
		zone_size = maxf(value, 1.0)
		_rebuild_resources()
		_refresh(true)

## Tiles per axis. Must match grid_size on the server. Only used to keep tiles
## inside the world; it is never iterated.
@export var grid_size := 2000

## Radius in tiles kept loaded around the player. 8 gives a 17x17 window.
@export var view_tiles := 8:
	set(value):
		view_tiles = maxi(value, 1)
		_refresh(true)

@export var thickness := 0.5:
	set(value):
		thickness = maxf(value, 0.01)
		_rebuild_resources()
		_refresh(true)

@export var color_a := Color(0.35, 0.45, 0.35):
	set(value):
		color_a = value
		_rebuild_resources()
		_refresh(true)

@export var color_b := Color(0.30, 0.40, 0.30):
	set(value):
		color_b = value
		_rebuild_resources()
		_refresh(true)

## What the window follows. Without it the window sits at the middle of the map.
@export var target_path: NodePath

var _tiles: Dictionary = {}          # Vector2i -> StaticBody3D
var _centre := Vector2i(2147483647, 0)
var _target: Node3D

var _mesh: BoxMesh
var _shape: BoxShape3D
var _mat_a: StandardMaterial3D
var _mat_b: StandardMaterial3D

func _ready() -> void:
	if target_path != NodePath() and has_node(target_path):
		_target = get_node(target_path)
	_rebuild_resources()
	_refresh(true)

func _process(_delta: float) -> void:
	_refresh(false)

## Tiles currently instantiated, for the debug overlay.
func loaded_tiles() -> int:
	return _tiles.size()

func _rebuild_resources() -> void:
	# One mesh, one shape and two materials shared by every tile: the window can
	# hold a few hundred of them, and they only differ by position and tint.
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(zone_size, thickness, zone_size)

	_shape = BoxShape3D.new()
	_shape.size = _mesh.size

	_mat_a = StandardMaterial3D.new()
	_mat_a.albedo_color = color_a
	_mat_b = StandardMaterial3D.new()
	_mat_b.albedo_color = color_b

	for key in _tiles:
		_tiles[key].free()
	_tiles.clear()
	_centre = Vector2i(2147483647, 0)

func _refresh(force: bool) -> void:
	if not is_node_ready():
		return

	var centre := _tile_of(_focus())
	if centre == _centre and not force:
		return
	_centre = centre

	# Drop tiles that fell outside the window.
	for key in _tiles.keys():
		var offset: Vector2i = key - centre
		if absi(offset.x) > view_tiles or absi(offset.y) > view_tiles:
			_tiles[key].queue_free()
			_tiles.erase(key)

	# Fill in the ones that came into it.
	for dx in range(-view_tiles, view_tiles + 1):
		for dy in range(-view_tiles, view_tiles + 1):
			var coords := centre + Vector2i(dx, dy)
			if coords.x < 0 or coords.y < 0 or coords.x >= grid_size or coords.y >= grid_size:
				continue
			if not _tiles.has(coords):
				_tiles[coords] = _make_tile(coords)

func _focus() -> Vector3:
	if _target != null:
		return _target.global_position
	var middle := grid_size * zone_size * 0.5
	return Vector3(middle, 0.0, middle)

func _tile_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / zone_size), floori(point.z / zone_size))

func _make_tile(coords: Vector2i) -> StaticBody3D:
	var tile := StaticBody3D.new()
	tile.name = "Zone_%d_%d" % [coords.x, coords.y]
	tile.position = Vector3(
		(coords.x + 0.5) * zone_size,
		0.0,
		(coords.y + 0.5) * zone_size,
	)
	add_child(tile)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _mesh
	mesh_instance.material_override = _mat_b if (coords.x + coords.y) % 2 else _mat_a
	tile.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.shape = _shape
	tile.add_child(collision)

	# Deliberately no owner: tiles are regenerated from the player's position
	# every run, so they must never be serialised into the scene file.
	return tile
