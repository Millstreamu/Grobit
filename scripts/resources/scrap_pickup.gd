class_name ResourcePickup
extends Area2D
## A dropped resource. Walking Grobit over it adds it to the run inventory.

@export var resource_id := "raw_scrap"
@export var amount := 1
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	var icon := GameData.resource_icon(resource_id)
	var color := GameData.resource_color(resource_id)
	sprite.texture = ContentLibrary.get_icon(icon, Vector2i(16, 16), color)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# Inventory is a finite grid: only take what fits, leave the rest on the floor.
	var placed := RunState.add(resource_id, amount)
	amount -= placed
	if amount <= 0:
		queue_free()
