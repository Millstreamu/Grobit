class_name GrobitAbilities
extends Node
## The three active abilities beyond Shoot: EMP, Shield, Regen.
## Balance values are exported for tuning. Controls are single key presses.

@export_category("EMP")
@export var emp_radius := 140.0
@export var emp_damage := 1
@export var emp_disable_seconds := 2.5
@export var emp_cooldown := 6.0

@export_category("Shield")
@export var shield_duration := 3.0
@export var shield_cooldown := 8.0

@export_category("Regen")
@export var regen_amount := 4
@export var regen_cooldown := 10.0

var _cooldowns := {"emp": 0.0, "shield": 0.0, "regen": 0.0}

signal ability_used(ability_id: String)


func _process(delta: float) -> void:
	for key: String in _cooldowns:
		_cooldowns[key] = maxf(_cooldowns[key] - delta, 0.0)
	if not _can_act():
		return
	if Input.is_action_just_pressed("ability_emp"):
		use_emp()
	if Input.is_action_just_pressed("ability_shield"):
		use_shield()
	if Input.is_action_just_pressed("ability_regen"):
		use_regen()


func cooldown_ratio(ability_id: String) -> float:
	var total := _cooldown_total(ability_id)
	if total <= 0.0:
		return 0.0
	return _cooldowns.get(ability_id, 0.0) / total


func is_ready(ability_id: String) -> bool:
	return _cooldowns.get(ability_id, 0.0) <= 0.0


func use_emp() -> bool:
	if not is_ready("emp"):
		return false
	var origin := _player().global_position
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D:
			continue
		if origin.distance_to((enemy as Node2D).global_position) > emp_radius:
			continue
		if enemy.has_method("disable"):
			enemy.disable(emp_disable_seconds)
		if enemy.has_method("take_damage"):
			enemy.take_damage(emp_damage)
	_cooldowns["emp"] = emp_cooldown
	ability_used.emit("emp")
	return true


func use_shield() -> bool:
	if not is_ready("shield"):
		return false
	_player().activate_shield(shield_duration)
	_cooldowns["shield"] = shield_cooldown
	ability_used.emit("shield")
	return true


func use_regen() -> bool:
	if not is_ready("regen"):
		return false
	_player().heal(regen_amount)
	_cooldowns["regen"] = regen_cooldown
	ability_used.emit("regen")
	return true


func _cooldown_total(ability_id: String) -> float:
	match ability_id:
		"emp": return emp_cooldown
		"shield": return shield_cooldown
		"regen": return regen_cooldown
	return 0.0


func _player() -> GrobitPlayer:
	return get_parent() as GrobitPlayer


func _can_act() -> bool:
	var grobit := _player()
	if grobit == null or grobit.health == null or grobit.health.is_dead():
		return false
	for bm: Node in get_tree().get_nodes_in_group("build_manager"):
		if bm.has_method("is_build_active") and bm.is_build_active():
			return false
	return true
