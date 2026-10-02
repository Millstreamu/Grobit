class_name BasicProjectile
extends Area2D

@export var speed := 360.0
@export var damage := 1
@export var lifetime := 1.5
## How many enemies this shot can pass THROUGH before stopping (0 = stops at the first).
## Ceramic weapons set this so a single lance skewers a line of enemies.
@export var pierce := 0
var direction := Vector2.RIGHT

var _hit := {}  # enemies already damaged by this shot (so pierce doesn't double-hit one)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		var bid := body.get_instance_id()
		if _hit.has(bid):
			return  # already skewered this one
		_hit[bid] = true
		body.take_damage(damage)
		if pierce <= 0:
			queue_free()
		else:
			pierce -= 1  # pass through and keep flying
	else:
		queue_free()  # a wall/obstacle stops even a piercing shot
