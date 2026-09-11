class_name GrobitPlayer
extends CharacterBody2D

const ATLAS_PATH := "res://content/atlases/prototype/prototype_atlas.json"
const SPRITE_NAME := "grobit"

@export_category("Movement")
@export var movement_speed := 150.0
@export var acceleration := 900.0
@export var deceleration := 1200.0
@export var rotation_speed := 10.0
@export_range(-360.0, 360.0, 1.0, "radians_as_degrees") var facing_offset := 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	var atlas := AtlasContent.new()
	if not atlas.load_json(ATLAS_PATH):
		push_error("Grobit cannot load its prototype atlas: %s" % atlas.last_error)
		set_physics_process(false)
		return
	var grobit_texture := atlas.get_sprite(SPRITE_NAME)
	if grobit_texture == null:
		push_error("Grobit sprite '%s' is missing from '%s'." % [SPRITE_NAME, ATLAS_PATH])
		set_physics_process(false)
		return
	sprite.texture = grobit_texture


func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var target_velocity := input_direction * movement_speed
	var rate := acceleration if not input_direction.is_zero_approx() else deceleration
	velocity = velocity.move_toward(target_velocity, rate * delta)

	# Facing follows intent rather than collision-adjusted velocity, so sliding along
	# a wall never turns Grobit unexpectedly. No input preserves the last facing.
	if not input_direction.is_zero_approx():
		var target_rotation := input_direction.angle() + facing_offset
		rotation = rotate_toward(rotation, target_rotation, rotation_speed * delta)

	move_and_slide()
