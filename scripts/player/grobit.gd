class_name GrobitPlayer
extends CharacterBody2D

signal died()

const SPRITE_NAME := "grobit"

@export_category("Movement")
@export var movement_speed := 150.0
@export var acceleration := 900.0
@export var deceleration := 1200.0
@export var rotation_speed := 10.0
## The Grobit sprite is drawn facing UP, so +90° aligns its facing with movement.
@export_range(-360.0, 360.0, 1.0, "radians_as_degrees") var facing_offset := PI / 2.0

@export_category("Survival")
@export var base_max_health := 10
## Damage multiplier applied while the Shield ability is active (0 = full block).
@export var shield_damage_multiplier := 0.0

@export_category("Gun")
const GUN_SPRITE_NAME := "grobit_gun_01"
## The gun sprite is also drawn facing UP, so +90° aims it along the shot line.
@export_range(-360.0, 360.0, 1.0, "radians_as_degrees") var gun_facing_offset := PI / 2.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var gun: Sprite2D = $Gun

var health: HealthComponent
var combat: PlayerCombat
var _shield_seconds := 0.0
var _flash_seconds := 0.0
var _input_locked := false


func _ready() -> void:
	add_to_group("player")
	sprite.texture = ContentLibrary.get_icon(SPRITE_NAME, Vector2i(32, 32), "6db7d4")
	gun.texture = ContentLibrary.get_icon(GUN_SPRITE_NAME, Vector2i(16, 16), "333333")
	combat = $Combat as PlayerCombat

	health = HealthComponent.new()
	health.name = "Health"
	# Permanent progression can raise Grobit's maximum health.
	health.max_health = base_max_health + int(MetaState.effect_total("max_health", 0.0))
	add_child(health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	# Servo Legs tech (or similar) scales base movement speed.
	movement_speed *= float(MetaState.effect_value("move_speed", 1.0))


func _physics_process(delta: float) -> void:
	if _shield_seconds > 0.0:
		_shield_seconds = maxf(_shield_seconds - delta, 0.0)
	if _flash_seconds > 0.0:
		_flash_seconds = maxf(_flash_seconds - delta, 0.0)
		sprite.modulate = Color(1, 0.4, 0.4)
	elif _shield_seconds > 0.0:
		sprite.modulate = Color(0.5, 0.8, 1.0)
	else:
		sprite.modulate = Color.WHITE

	_update_gun()

	if _input_locked:
		velocity = Vector2.ZERO
		return

	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _build_active():  # in build mode WASD drives the placement cursor, not Grobit
		input_direction = Vector2.ZERO
	var target_velocity := input_direction * movement_speed
	var rate := acceleration if not input_direction.is_zero_approx() else deceleration
	velocity = velocity.move_toward(target_velocity, rate * delta)

	if not input_direction.is_zero_approx():
		var target_rotation := input_direction.angle() + facing_offset
		rotation = rotate_toward(rotation, target_rotation, rotation_speed * delta)

	move_and_slide()


# Points the gun at the enemy the auto-attack is targeting; otherwise it lines up
# with the body's facing. Gun rotation is set in global space so the body's own
# rotation doesn't compound with it.
func _update_gun() -> void:
	if combat == null:
		return
	var target := combat.get_aim_target()
	if target != null:
		gun.global_rotation = global_position.angle_to_point(target.global_position) + gun_facing_offset
	else:
		gun.global_rotation = rotation


## Enemies and hazards call this. Shield reduces incoming damage.
func take_damage(amount: int) -> void:
	if health == null or health.is_dead():
		return
	var final_amount := amount
	if _shield_seconds > 0.0:
		final_amount = int(round(amount * shield_damage_multiplier))
	health.take_damage(final_amount)


func heal(amount: int) -> void:
	if health != null:
		health.heal(amount)


func activate_shield(seconds: float) -> void:
	_shield_seconds = maxf(_shield_seconds, seconds)


func is_shielded() -> bool:
	return _shield_seconds > 0.0


func set_input_locked(locked: bool) -> void:
	_input_locked = locked
	if locked:
		velocity = Vector2.ZERO


## Used by the respawn system to move Grobit and restore some health.
func respawn_at(world_position: Vector2, to_health := -1) -> void:
	global_position = world_position
	velocity = Vector2.ZERO
	if health != null:
		health.revive(to_health)


func _on_damaged(_amount: int) -> void:
	_flash_seconds = 0.15


## The world-space direction Grobit is visually facing (independent of the sprite's
## drawn orientation), e.g. for seeding the build cursor in front of Grobit.
func facing_direction() -> Vector2:
	return Vector2.RIGHT.rotated(rotation - facing_offset)


func _build_active() -> bool:
	for bm: Node in get_tree().get_nodes_in_group("build_manager"):
		if bm.has_method("is_build_active") and bm.is_build_active():
			return true
	return false


func _on_died() -> void:
	died.emit()
