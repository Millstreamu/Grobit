class_name Spawner
extends StaticBody2D
## A destructible enemy SOURCE (Phase 2.4). HarvestMode places these at the breached doors and emits
## besiegers from them. The bot's turret can shoot a spawner down (it sits on the enemy hit layer) to
## CUT the flow from it — real pressure relief. BUT once Heat reaches FULL_ALERT the facility is fully
## alerted: spawners are HARDENED (damage won't drop them) and even ones you already wrecked come back
## online, so you can't clear your way out any more.

const MAX_HP := 8
const HIT_LAYER := 2  # the "enemy" layer the bot's projectiles (mask 3) scan — lets the turret hit it

var destroyed := false
var _hp := MAX_HP
var _flash := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("spawners")
	collision_layer = HIT_LAYER
	collision_mask = 0
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 11.0
	col.shape = shape
	add_child(col)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_refresh()


## True when this spawner can still emit enemies: while intact, OR always once the facility is on
## full alert (hardened — even a wrecked spawner comes back online).
func can_source() -> bool:
	return (not destroyed) or RunState.heat_tier() == RunState.HEAT_FULL_ALERT_TIER


func take_damage(amount: int) -> void:
	_flash = 0.12
	# Hardened on full alert — shrugs off fire entirely.
	if RunState.heat_tier() == RunState.HEAT_FULL_ALERT_TIER:
		return
	if destroyed:
		return
	_hp -= amount
	if _hp <= 0:
		destroyed = true
		_refresh()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		if _sprite != null:
			_sprite.modulate = Color(1, 0.75, 0.75)
	elif _sprite != null:
		_sprite.modulate = Color(1, 1, 1)


func _refresh() -> void:
	if _sprite == null:
		return
	# Dim + shrink when wrecked; bright when it can still source.
	var col := "4a3a66" if destroyed else "8a5ad0"
	var sz := 18 if destroyed else 24
	_sprite.texture = ContentLibrary.get_icon("enemy_spawner", Vector2i(sz, sz), col)
