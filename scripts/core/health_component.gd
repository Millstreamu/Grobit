class_name HealthComponent
extends Node
## Reusable health/damage/death for any actor. Emits signals so UI and feedback
## can react without the owner knowing about them.

signal health_changed(current: int, maximum: int)
signal damaged(amount: int)
signal died()

@export var max_health := 10
@export var invulnerable_seconds := 0.4

var health := 10
var _invuln := 0.0
var _dead := false


func _ready() -> void:
	# Actors spawn at full health; max may have been configured before add_child.
	health = max_health
	health_changed.emit(health, max_health)


func _process(delta: float) -> void:
	if _invuln > 0.0:
		_invuln = maxf(_invuln - delta, 0.0)


func set_max_health(value: int, refill := true) -> void:
	max_health = maxi(1, value)
	if refill:
		health = max_health
	else:
		health = mini(health, max_health)
	health_changed.emit(health, max_health)


## Raises maximum health and heals by the same amount (e.g. a repair reward).
func add_max_health(amount: int) -> void:
	if amount <= 0:
		return
	max_health += amount
	health += amount
	health_changed.emit(health, max_health)


func take_damage(amount: int) -> void:
	if _dead or amount <= 0 or _invuln > 0.0:
		return
	health = maxi(0, health - amount)
	_invuln = invulnerable_seconds
	damaged.emit(amount)
	health_changed.emit(health, max_health)
	if health <= 0:
		_dead = true
		died.emit()


func heal(amount: int) -> void:
	if _dead or amount <= 0:
		return
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)


func revive(to_health := -1) -> void:
	_dead = false
	_invuln = invulnerable_seconds
	health = to_health if to_health > 0 else max_health
	health = clampi(health, 1, max_health)
	health_changed.emit(health, max_health)


func is_dead() -> bool:
	return _dead
