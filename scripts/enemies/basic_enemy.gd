class_name BasicEnemy
extends CharacterBody2D

const ATLAS_PATH := "res://content/atlases/prototype/prototype_atlas.json"
const PICKUP_SCENE := preload("res://scenes/resources/scrap_pickup.tscn")

@export var movement_speed := 55.0
@export var max_health := 3
var health: int
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	var atlas := AtlasContent.new()
	if not atlas.load_json(ATLAS_PATH):
		push_error("Basic enemy cannot load its prototype atlas: %s" % atlas.last_error)
		set_physics_process(false)
		return
	sprite.texture = atlas.get_sprite("enemy_basic")


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
	else:
		velocity = global_position.direction_to(player.global_position) * movement_speed
	move_and_slide()


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		die()


func die() -> void:
	var pickup := PICKUP_SCENE.instantiate() as Node2D
	pickup.global_position = global_position
	get_parent().add_child(pickup)
	queue_free()
