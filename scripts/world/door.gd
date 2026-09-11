class_name Door
extends StaticBody2D
## A one-tile door. Open = passable (no collision, open sprite). Locked = solid.
## Rooms lock their own doors on activation and unlock them once cleared.

@export var tile_size := Vector2i(32, 32)

var locked := false
var _sprite: Sprite2D
var _collision: CollisionShape2D


func _ready() -> void:
	add_to_group("doors")
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_collision = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(tile_size)
	_collision.shape = rect
	add_child(_collision)
	_refresh()


func lock() -> void:
	locked = true
	_refresh()


func unlock() -> void:
	locked = false
	_refresh()


func _refresh() -> void:
	if _sprite == null:
		return
	if locked:
		_sprite.texture = ContentLibrary.get_tile("door_closed", tile_size)
	else:
		_sprite.texture = ContentLibrary.get_tile("door_open", tile_size)
	_collision.set_deferred("disabled", not locked)
