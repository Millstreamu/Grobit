class_name BasicEnemy
extends CharacterBody2D
## Data-driven enemy. Stats, sprite, size and behaviour come from the enemy type
## definition (data/game/enemies.json) keyed by enemy_id. Supports a melee chaser
## and a ranged "keep distance and shoot" behaviour. Rooms may pass a per-wave
## bonus_health / speed_mult for escalation.

const PICKUP_SCENE := preload("res://scenes/resources/scrap_pickup.tscn")
const ENEMY_PROJECTILE_SCENE := preload("res://scenes/combat/enemy_projectile.tscn")

@export var enemy_id := "basic_enemy"
@export var bonus_health := 0
@export var speed_mult := 1.0

var max_health := 3
var movement_speed := 55.0
var health: int
var _behavior := "melee"
var _melee := {}
var _ranged := {}
var _size := 16
var _disabled_seconds := 0.0
var _attack_cooldown := 0.0
@onready var sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("enemies")
	var def: Dictionary = GameData.enemies.get(enemy_id, {})
	_size = int(def.get("size", 16))
	max_health = int(def.get("health", 3)) + bonus_health
	movement_speed = float(def.get("speed", 55.0)) * speed_mult
	_behavior = String(def.get("behavior", "melee"))
	_melee = def.get("melee", {})
	_ranged = def.get("ranged", {})
	health = max_health

	sprite.texture = ContentLibrary.get_icon(String(def.get("sprite", "enemy_basic")), Vector2i(_size, _size), String(def.get("color", "")))
	# Per-instance collision so different sizes don't share one shape.
	var circle := CircleShape2D.new()
	circle.radius = maxf(4.0, _size * 0.45)
	_collision.shape = circle


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _disabled_seconds > 0.0:
		_disabled_seconds = maxf(_disabled_seconds - delta, 0.0)
		sprite.modulate = Color(0.6, 0.6, 1.0)
		velocity = Vector2.ZERO
		move_and_slide()
		return
	sprite.modulate = Color.WHITE

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _behavior == "ranged":
		_ranged_behavior(player)
	else:
		_melee_behavior(player)
	move_and_slide()


func _melee_behavior(player: Node2D) -> void:
	velocity = global_position.direction_to(player.global_position) * movement_speed
	if global_position.distance_to(player.global_position) <= float(_melee.get("range", 26)):
		_try_melee(player)


func _ranged_behavior(player: Node2D) -> void:
	var distance := global_position.distance_to(player.global_position)
	var desired := float(_ranged.get("desired_distance", 140))
	var to_player := global_position.direction_to(player.global_position)
	if distance > desired:
		velocity = to_player * movement_speed
	elif distance < desired * 0.7:
		velocity = -to_player * movement_speed
	else:
		velocity = Vector2.ZERO
	if distance <= float(_ranged.get("range", 220)):
		_try_shoot(player)


func _try_melee(player: Node2D) -> void:
	if _attack_cooldown > 0.0:
		return
	if player.has_method("take_damage"):
		player.take_damage(int(_melee.get("damage", 1)))
	_attack_cooldown = float(_melee.get("interval", 1.0))


func _try_shoot(player: Node2D) -> void:
	if _attack_cooldown > 0.0:
		return
	var shot := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	shot.global_position = global_position
	shot.direction = global_position.direction_to(player.global_position)
	shot.damage = int(_ranged.get("damage", 1))
	shot.speed = float(_ranged.get("projectile_speed", 200))
	var world := get_tree().current_scene
	if world == null:
		world = get_parent()
	world.add_child(shot)
	_attack_cooldown = float(_ranged.get("interval", 1.5))


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		die()


## Pixel size for selection/target highlights.
func selection_size() -> int:
	return _size


## Temporarily stops the enemy acting (used by the EMP ability).
func disable(seconds: float) -> void:
	_disabled_seconds = maxf(_disabled_seconds, seconds)


func die() -> void:
	_spawn_drops()
	queue_free()


func _spawn_drops() -> void:
	var drops := _drop_table()
	var index := 0
	for drop: Dictionary in drops:
		if randf() > float(drop.get("chance", 1.0)):
			continue
		var amount := randi_range(int(drop.get("min", 1)), int(drop.get("max", 1)))
		if amount <= 0:
			continue
		var pickup := PICKUP_SCENE.instantiate()
		pickup.resource_id = String(drop.get("resource", "raw_scrap"))
		pickup.amount = amount
		var angle := TAU * (float(index) / maxf(1.0, float(drops.size())))
		pickup.global_position = global_position + Vector2.RIGHT.rotated(angle) * 14.0
		get_parent().add_child(pickup)
		index += 1


func _drop_table() -> Array:
	# Prefer tool-authored drops (generation.json), fall back to area.json.
	var drops: Dictionary = GameData.generation.get("resource_drops", GameData.area(RunState.area_id).get("resource_drops", {}))
	var table: Variant = drops.get(enemy_id, null)
	if table is Array:
		return table
	return [{"resource": "raw_scrap", "min": 1, "max": 2, "chance": 1.0}]
