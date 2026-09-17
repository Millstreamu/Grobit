class_name EnemyProjectile
extends Area2D
## Fired by ranged enemies. Damages the player and dies on the player or a wall.

@export var speed := 200.0
@export var damage := 1
@export var lifetime := 3.0
var direction := Vector2.RIGHT
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	sprite.texture = ContentLibrary.get_icon("enemy_shot", Vector2i(8, 8), "ff5a5a")
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
