class_name Spawner
extends Node2D
## A wall-mounted spawn point in a spawner room. Purely a marker + sprite: the
## owning Room decides when to spawn a wave and uses these as the spawn locations.

const SPRITE_NAME := "wall_spawner"

## Enemies appear this far toward the room interior from the wall.
var spawn_offset := Vector2(0, 14)
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("spawners")
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon(SPRITE_NAME, Vector2i(32, 32), "7a3aa0")
	add_child(_sprite)


func spawn_position() -> Vector2:
	return global_position + spawn_offset
