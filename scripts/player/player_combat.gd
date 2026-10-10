class_name PlayerCombat
extends Node
## Grobit's Shoot: a MANUAL turret. Auto-AIMS at the nearest (or Tab-picked) enemy in range; the
## player taps [Space] / LMB to fire one shot per press (cooldown caps the rate). Shoot upgrades (e.g. Aegis Rounds)
## hook in here. (Firing used to be automatic; it's now the only counter-play in a hot room — see
## docs/DESIGN_SPEC.md §0.2.)

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

@export_category("Weapon-stat fallbacks + range")
## There is NO built-in gun: all firepower comes from a placed weapon module drawing the bot's
## loaded ammo (see FactoryGrid.weapon_stats + RunState.consume_ammo). These damage/cooldown/speed
## fallbacks are only used if a
## weapon def omits a field; attack_range is how far Grobit auto-targets.
@export var damage := 1
@export var attack_range := 220.0
@export var cooldown := 0.55
@export var projectile_speed := 320.0

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
	# MANUAL turret: the gun auto-AIMS (nearest / Tab-picked target); the player taps [Space] (or LMB)
	# to fire ONE shot per press. Cooldown still caps how fast consecutive shots can land (fire rate).
	if Input.is_action_just_pressed("attack"):
		attack_nearest()


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
	# Firepower comes ONLY from a weapon module in the bot's MODULE BAY — no built-in gun. The
	# weapon draws from the bot's loaded ammo reserve (made in the workshop, loaded at launch); no
	# weapon or no ammo → no shot. Ammo Loader modules speed up the fire rate.
	if RunState.bay == null:
		return false
	var shot := RunState.bay.weapon_stats()
	if shot.is_empty():
		return false
	if not RunState.consume_ammo(String(shot.get("ammo", ""))):
		return false  # out of ammo — make more in the workshop and reload next run
	var dmg := int(round(float(shot.get("damage", damage))))
	var cd := float(shot.get("cooldown", cooldown)) / maxf(RunState.bay.fire_rate_multiplier(), 0.01)
	var spd := float(shot.get("projectile_speed", projectile_speed))
	var pellets := maxi(1, int(shot.get("pellets", 1)))       # plastic: spread
	var spread := deg_to_rad(float(shot.get("spread_deg", 0.0)))
	var pierce := int(shot.get("pierce", 0))                  # ceramic: pierce
	var origin := (get_parent() as Node2D).global_position
	var base_dir := origin.direction_to(target.global_position)
	var world := get_tree().current_scene
	if world == null:
		world = get_parent().get_parent()
	for i in pellets:
		# Fan the pellets evenly across the spread arc (a single pellet fires dead-on).
		var offset := 0.0
		if pellets > 1:
			offset = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(pellets - 1))
		var projectile := PROJECTILE_SCENE.instantiate() as BasicProjectile
		projectile.global_position = origin
		projectile.direction = base_dir.rotated(offset)
		projectile.damage = dmg
		projectile.speed = spd
		projectile.pierce = pierce
		world.add_child(projectile)
	_cooldown_remaining = cd
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
