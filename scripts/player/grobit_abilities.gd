class_name GrobitAbilities
extends Node
## One equipped active ability, chosen at the start of the run and triggered with
## Space. Behaviour + balance come from data (data/game/abilities.json). Shooting
## is now automatic (see PlayerCombat), so Space is free for the ability.

signal ability_used(ability_id: String)

var _ability_id := ""
var _def: Dictionary = {}
var _cooldown := 0.0


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _ability_id.is_empty() or not _can_act():
		return
	if Input.is_action_just_pressed("attack"):
		use()


## Equip an ability by id (from the run-start choice, or a future mid-run switch).
func equip(ability_id: String) -> void:
	_ability_id = ability_id
	_def = GameData.abilities.get(ability_id, {})
	# Brief cooldown so the button press that equipped it doesn't also fire it.
	_cooldown = 0.25


func equipped_id() -> String:
	return _ability_id


func equipped_name() -> String:
	return String(_def.get("name", _ability_id))


func is_ready() -> bool:
	return _cooldown <= 0.0


func cooldown_ratio() -> float:
	var total := float(_def.get("cooldown", 1.0))
	return _cooldown / maxf(0.01, total)


func use() -> bool:
	if _cooldown > 0.0 or _ability_id.is_empty():
		return false
	match _ability_id:
		"emp":
			_use_emp()
		"shield":
			_player().activate_shield(float(_def.get("duration", 3.0)))
		"regen":
			_player().heal(int(_def.get("amount", 4)))
		"overload":
			_damage_nearby(float(_def.get("radius", 150.0)), int(_def.get("damage", 4)), 0.0)
		_:
			return false
	_cooldown = float(_def.get("cooldown", 6.0))
	ability_used.emit(_ability_id)
	return true


func _use_emp() -> void:
	_damage_nearby(float(_def.get("radius", 140.0)), int(_def.get("damage", 1)), float(_def.get("disable_seconds", 2.5)))


# Affects every enemy within radius: optional disable, then damage.
func _damage_nearby(radius: float, damage: int, disable_seconds: float) -> void:
	var origin := _player().global_position
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D:
			continue
		if origin.distance_to((enemy as Node2D).global_position) > radius:
			continue
		if disable_seconds > 0.0 and enemy.has_method("disable"):
			enemy.disable(disable_seconds)
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage)


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
