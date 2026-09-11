class_name BasicEnemy
extends CharacterBody2D

const PICKUP_SCENE := preload("res://scenes/resources/scrap_pickup.tscn")
const SPRITE_NAME := "enemy_basic"

@export var enemy_id := "basic_enemy"
@export var movement_speed := 55.0
@export var max_health := 3

@export_category("Melee")
@export var melee_range := 26.0
@export var melee_damage := 1
@export var melee_interval := 1.0

var health: int
var _disabled_seconds := 0.0
var _melee_cooldown := 0.0
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	sprite.texture = ContentLibrary.get_icon(SPRITE_NAME, Vector2i(32, 32), "d46d6d")


func _physics_process(delta: float) -> void:
	_melee_cooldown = maxf(_melee_cooldown - delta, 0.0)
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
	else:
		velocity = global_position.direction_to(player.global_position) * movement_speed
		if global_position.distance_to(player.global_position) <= melee_range:
			_try_melee(player)
	move_and_slide()


func _try_melee(player: Node2D) -> void:
	if _melee_cooldown > 0.0:
		return
	if player.has_method("take_damage"):
		player.take_damage(melee_damage)
	_melee_cooldown = melee_interval


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		die()


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
	var area: Dictionary = GameData.area(RunState.area_id)
	var table: Variant = area.get("resource_drops", {}).get(enemy_id, null)
	if table is Array:
		return table
	# Fallback so the enemy still drops something outside a configured run.
	return [{"resource": "raw_scrap", "min": 1, "max": 2, "chance": 1.0}]
