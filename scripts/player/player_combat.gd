class_name PlayerCombat
extends Node
## Grobit's Shoot ability: auto-targets and fires at the nearest enemy in range.

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

@export_category("Basic Attack")
@export var damage := 1
@export var attack_range := 220.0
@export var cooldown := 0.4
@export var projectile_speed := 360.0

var _cooldown_remaining := 0.0


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if not _can_act():
		return
	if Input.is_action_pressed("attack"):
		attack_nearest()


func cooldown_ratio() -> float:
	if cooldown <= 0.0:
		return 0.0
	return _cooldown_remaining / cooldown


func attack_nearest() -> bool:
	if _cooldown_remaining > 0.0:
		return false
	var target := _nearest_enemy()
	if target == null:
		return false
	var projectile := PROJECTILE_SCENE.instantiate() as BasicProjectile
	projectile.global_position = (get_parent() as Node2D).global_position
	projectile.direction = projectile.global_position.direction_to(target.global_position)
	projectile.damage = damage
	projectile.speed = projectile_speed
	var world := get_tree().current_scene
	if world == null:
		world = get_parent().get_parent()
	world.add_child(projectile)
	_cooldown_remaining = cooldown
	return true


func _can_act() -> bool:
	var grobit := get_parent() as GrobitPlayer
	if grobit != null and (grobit.health == null or grobit.health.is_dead()):
		return false
	for bm: Node in get_tree().get_nodes_in_group("build_manager"):
		if bm.has_method("is_build_active") and bm.is_build_active():
			return false
	return true


func _nearest_enemy() -> Node2D:
	var origin := (get_parent() as Node2D).global_position
	var nearest: Node2D
	var nearest_distance := attack_range
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Node2D:
			continue
		var distance := origin.distance_to(candidate.global_position)
		if distance <= nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest
