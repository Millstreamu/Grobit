class_name InteractableObject
extends StaticBody2D
## Base for solid, grid-locked objects the player interacts with using F
## (scrap nodes, repair stations, crafting machines). Provides a solid body so
## Grobit can't walk through it, plus a slightly larger Area2D "range" that tracks
## when the player is close enough to interact. Interaction itself is driven by
## SelectionManager (nearest interactable only).
##
## Subclasses override _configure() to set sprite/size/extra groups, and the
## can_interact/interact/interaction_prompt hooks. They must NOT define _ready().

var interact_radius := 26.0
var solid_size := Vector2(28, 28)

var _sprite_id := ""
var _sprite_color := ""
var _sprite: Sprite2D
var _in_range := false


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 1  # solid; the player (mask includes layer 1) collides with it
	_configure()

	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon(_sprite_id, Vector2i(solid_size), _sprite_color)
	add_child(_sprite)

	var body_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = solid_size
	body_shape.shape = rect
	add_child(body_shape)

	var range_area := Area2D.new()
	range_area.collision_mask = 1
	range_area.monitoring = true
	var range_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = interact_radius
	range_shape.shape = circle
	range_area.add_child(range_shape)
	add_child(range_area)
	range_area.body_entered.connect(_on_range_entered)
	range_area.body_exited.connect(_on_range_exited)

	_post_setup()


## Override to set _sprite_id / _sprite_color / solid_size / interact_radius / groups.
func _configure() -> void:
	pass


## Override for any extra work after the body/range are built.
func _post_setup() -> void:
	pass


func can_interact() -> bool:
	return _in_range


func interact() -> void:
	pass


func interaction_prompt() -> String:
	return ""


func selection_size() -> int:
	return int(maxf(solid_size.x, solid_size.y))


func _on_range_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = true


func _on_range_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = false


func _notify(text: String) -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("log_message"):
			hud.log_message(text)
