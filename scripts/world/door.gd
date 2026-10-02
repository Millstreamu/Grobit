class_name Door
extends StaticBody2D
## A one-tile door. Closed = solid (blocks movement + light); open = passable. Doors
## start closed and the player toggles them with F (they're interactables). Combat/
## spawner rooms can SEAL a door shut for the duration of a wave (lock/unlock) — a
## sealed door can't be opened by hand until the room is cleared.

@export var tile_size := Vector2i(32, 32)
## How close the player must be (px) to toggle the door with F.
@export var interact_radius := 34.0

var _open := false     # player-controlled state; doors start closed
var _forced := false   # room combat-seal: can't be opened by hand while true
var _sprite: Sprite2D
var _collision: CollisionShape2D
var _occluder: LightOccluder2D


func _ready() -> void:
	add_to_group("doors")
	add_to_group("interactables")  # so F (SelectionManager/HUD) can toggle it
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_collision = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(tile_size)
	_collision.shape = rect
	add_child(_collision)
	# Blocks light only while solid (see LightingSystem): a closed door is a wall to
	# both movement and vision. Hidden when open so light passes through.
	_occluder = LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	var half := Vector2(tile_size) * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	_occluder.occluder = poly
	add_child(_occluder)
	_refresh()


## Solid to movement/light when sealed by a room, or simply closed.
func _solid() -> bool:
	return _forced or not _open


# ---- room combat seal (not the player's manual open/close) ----

func lock() -> void:
	_forced = true
	_refresh()


func unlock() -> void:
	_forced = false
	_open = true  # clearing a room opens its exits; the player can close them again
	_refresh()


# ---- interactable interface (F) ----

func can_interact() -> bool:
	if _forced:
		return false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return player != null and global_position.distance_to(player.global_position) <= interact_radius


## Low priority: any pickup/station in range is chosen over a door, so an item sitting
## in a doorway can still be grabbed to clear the way.
func interact_priority() -> int:
	return -10


func interact() -> void:
	if _forced:
		return
	if _open:
		# Don't close a door on top of the player (they'd be stuck in the wall).
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and global_position.distance_to(player.global_position) < 22.0:
			return
		_open = false
	else:
		_open = true
	_refresh()


func interaction_prompt() -> String:
	return "[F] Close door" if _open else "[F] Open door"


func selection_size() -> int:
	return int(tile_size.x)


func _refresh() -> void:
	if _sprite == null:
		return
	_sprite.texture = ContentLibrary.get_tile("door_closed" if _solid() else "door_open", tile_size)
	_collision.set_deferred("disabled", not _solid())
	if _occluder != null:
		_occluder.visible = _solid()  # hidden occluders don't cast shadows
