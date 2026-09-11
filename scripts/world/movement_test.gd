extends Node2D

const TILESET_PATH := "res://content/tilesets/prototype/prototype_environment.json"
const ROOM_SIZE := Vector2i(20, 14)

@onready var tile_layer: Node2D = $Tiles
@onready var walls: StaticBody2D = $Walls


func _ready() -> void:
	var tileset := TilesetContent.new()
	if not tileset.load_json(TILESET_PATH):
		push_error("Movement test cannot load its prototype tileset: %s" % tileset.last_error)
		return
	var floor_texture := tileset.get_tile("floor_clean")
	var wall_texture := tileset.get_tile("wall")
	if floor_texture == null or wall_texture == null:
		push_error("Movement test requires 'floor_clean' and 'wall' tiles in '%s'." % TILESET_PATH)
		return
	if tileset.get_tile_data("wall").get("collision", false) != true:
		push_error("Movement test wall tile has no collision metadata in '%s'." % TILESET_PATH)
		return

	_build_room(floor_texture, wall_texture, Vector2i(tileset.tile_width, tileset.tile_height))


func _build_room(floor_texture: Texture2D, wall_texture: Texture2D, tile_size: Vector2i) -> void:
	for y in ROOM_SIZE.y:
		for x in ROOM_SIZE.x:
			var is_wall := x == 0 or y == 0 or x == ROOM_SIZE.x - 1 or y == ROOM_SIZE.y - 1
			var tile := Sprite2D.new()
			tile.texture = wall_texture if is_wall else floor_texture
			tile.position = Vector2(x * tile_size.x, y * tile_size.y)
			tile_layer.add_child(tile)

	# Merge the collidable perimeter tiles into four simple physics shapes.
	_add_wall_shape(Vector2((ROOM_SIZE.x - 1) * tile_size.x * 0.5, 0.0), Vector2(ROOM_SIZE.x * tile_size.x, tile_size.y))
	_add_wall_shape(Vector2((ROOM_SIZE.x - 1) * tile_size.x * 0.5, (ROOM_SIZE.y - 1) * tile_size.y), Vector2(ROOM_SIZE.x * tile_size.x, tile_size.y))
	_add_wall_shape(Vector2(0.0, (ROOM_SIZE.y - 1) * tile_size.y * 0.5), Vector2(tile_size.x, (ROOM_SIZE.y - 2) * tile_size.y))
	_add_wall_shape(Vector2((ROOM_SIZE.x - 1) * tile_size.x, (ROOM_SIZE.y - 1) * tile_size.y * 0.5), Vector2(tile_size.x, (ROOM_SIZE.y - 2) * tile_size.y))


func _add_wall_shape(shape_position: Vector2, shape_size: Vector2) -> void:
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = shape_size
	collision.shape = rectangle
	collision.position = shape_position
	walls.add_child(collision)
