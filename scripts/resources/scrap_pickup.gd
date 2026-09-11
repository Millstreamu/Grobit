class_name ScrapPickup
extends Area2D

const ATLAS_PATH := "res://content/atlases/prototype/prototype_atlas.json"
@export var amount := 1
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	var atlas := AtlasContent.new()
	if not atlas.load_json(ATLAS_PATH):
		push_error("Scrap pickup cannot load its prototype atlas: %s" % atlas.last_error)
		return
	sprite.texture = atlas.get_sprite("scrap_metal")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var counter := get_tree().get_first_node_in_group("resource_counter")
	if counter != null:
		counter.add_scrap_metal(amount)
	queue_free()
