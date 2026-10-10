class_name ResourcePickup
extends Area2D
## A dropped resource on the floor. NOT auto-collected — stand near it and press F
## to pick it up (obeys inventory space). Non-solid, so Grobit can walk over it.

@export var resource_id := "copper_scrap"
@export var amount := 1

var _in_range := false
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("pickups")
	sprite.texture = ContentLibrary.get_icon(GameData.resource_icon(resource_id), Vector2i(16, 16), GameData.resource_color(resource_id))
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = false


func can_interact() -> bool:
	return _in_range and amount > 0


func selection_size() -> int:
	return 16


func interaction_prompt() -> String:
	return "[F] Pick up %s x%d" % [GameData.resource_name(resource_id), amount]


func interact() -> void:
	# Tech Data on the top bar is uncapped and always collectable. Everything else — typed scrap
	# included (it now feeds the inventory grid) — needs a free cell.
	var off_grid := resource_id in RunState.BAR_CURRENCIES
	if not off_grid and not RunState.has_space():
		for hud: Node in get_tree().get_nodes_in_group("hud"):
			if hud.has_method("log_message"):
				hud.log_message("Inventory full.")
		return
	var placed := RunState.deposit(resource_id, amount)
	amount -= placed
	if amount <= 0:
		queue_free()
