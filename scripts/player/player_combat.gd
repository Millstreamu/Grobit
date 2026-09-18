class_name PlayerCombat
extends Node
## Grobit's Shoot: fully automatic. Auto-targets and fires at the nearest (or
## Tab-picked) enemy in range whenever off cooldown — no button needed. Space is
## free for the equipped ability. Shoot upgrades (e.g. Aegis Rounds) hook in here.

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

@export_category("Basic Attack")
@export var damage := 1
@export var attack_range := 220.0
@export var cooldown := 0.4
@export var projectile_speed := 360.0

@export_category("Aegis Rounds upgrade")
@export var aegis_shots := 3
@export var aegis_shield_seconds := 1.0

var _cooldown_remaining := 0.0
var _picked_target: Node2D
var _shot_count := 0
var _aegis := false


func _ready() -> void:
	# Shoot upgrades come from permanent tech for now (see docs for the run-based plan).
	_aegis = MetaState.has_tech("aegis_rounds")


## Turns on the Aegis Rounds shoot upgrade for this run (e.g. a repair reward).
func enable_aegis() -> void:
	_aegis = true


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if not _can_act():
		return
	if Input.is_action_just_pressed("cycle_target"):
		_cycle_target()
	attack_nearest()  # automatic — fires whenever a target is in range and off cooldown


## The enemy Shoot is currently aiming at: the manually picked target if it's still
## valid and in range, otherwise the nearest enemy. Used by the gun + selector.
func get_aim_target() -> Node2D:
	return _resolve_target()


func cooldown_ratio() -> float:
	if cooldown <= 0.0:
		return 0.0
	return _cooldown_remaining / cooldown


func attack_nearest() -> bool:
	if _cooldown_remaining > 0.0:
		return false
	var target := _resolve_target()
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
	_on_shot_fired()
	return true


# Shoot-upgrade hook. Aegis Rounds: every N shots, grant Grobit a brief shield.
func _on_shot_fired() -> void:
	_shot_count += 1
	if _aegis and aegis_shots > 0 and _shot_count % aegis_shots == 0:
		var grobit := get_parent() as GrobitPlayer
		if grobit != null:
			grobit.activate_shield(aegis_shield_seconds)


func _can_act() -> bool:
	var grobit := get_parent() as GrobitPlayer
	if grobit != null and (grobit.health == null or grobit.health.is_dead()):
		return false
	for bm: Node in get_tree().get_nodes_in_group("build_manager"):
		if bm.has_method("is_build_active") and bm.is_build_active():
			return false
	return true


# The picked target if it is still alive and in range; otherwise nearest (and the
# stale pick is dropped). This keeps the pick "sticky" until it dies or you walk away.
func _resolve_target() -> Node2D:
	if _picked_target != null and is_instance_valid(_picked_target) and _in_range(_picked_target):
		return _picked_target
	_picked_target = null
	return _nearest_enemy()


# Tab steps to the next enemy in range (by distance), wrapping around. First press
# picks the nearest; subsequent presses advance from the current pick.
func _cycle_target() -> void:
	var enemies := _enemies_in_range()
	if enemies.is_empty():
		_picked_target = null
		return
	var index := enemies.find(_picked_target)
	_picked_target = enemies[(index + 1) % enemies.size()] if index != -1 else enemies[0]


func _enemies_in_range() -> Array[Node2D]:
	var origin := (get_parent() as Node2D).global_position
	var result: Array[Node2D] = []
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if candidate is Node2D and origin.distance_to((candidate as Node2D).global_position) <= attack_range:
			result.append(candidate)
	result.sort_custom(func(a, b): return origin.distance_to(a.global_position) < origin.distance_to(b.global_position))
	return result


func _in_range(node: Node2D) -> bool:
	return (get_parent() as Node2D).global_position.distance_to(node.global_position) <= attack_range


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
