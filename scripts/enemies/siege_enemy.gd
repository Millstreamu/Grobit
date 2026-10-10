class_name SiegeEnemy
extends CharacterBody2D
## A besieger drawn in by the colony's harvesting + the facility's Heat (Phase 2.4). Two tiers:
##   TIER 1 (grunt)   — makes for the nearest deployed GOBLIN and attacks it (permadeath stakes).
##   TIER 2 (bruiser) — appears once Heat crosses HEAT_BOT_THREAT; tankier + hits harder and goes for
##                      the SCRAPBOT itself (the bot can be destroyed → game over). Tinted orange.
## HarvestMode rolls the tier by Heat when it spawns one. Killable — the manual turret cuts them down.

const SPEED := 58.0
const ATTACK_RANGE := 16.0
const ATTACK_CD := 0.8
const DAMAGE := 1
const MAX_HP := 3

## Tier-2 bruiser stats.
const BRUISER_SPEED := 46.0
const BRUISER_DAMAGE := 2
const BRUISER_HP := 6

var tier := 1
var _speed := SPEED
var _damage := DAMAGE
var _max_hp := MAX_HP

## Layer 2 is the "enemy" layer the bot's projectiles (mask 3) scan — being on it is what lets
## the auto-turrets actually connect. Mask stays 0 so besiegers don't physically collide with
## walls/goblins/the bot; they just make a straight-line approach (room-local).
const HIT_LAYER := 2

var _hp := MAX_HP
var _cd := 0.0
var _flash := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("enemies")        # so the bot's weapons auto-target it (Slice 3)
	add_to_group("siege_enemies")
	collision_layer = HIT_LAYER    # detectable by the bot's projectiles
	collision_mask = 0             # room-local straight-line approach (nav refined later)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 7.0
	col.shape = shape
	add_child(col)
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon("enemy_basic", Vector2i(16, 16), "c0504a")
	add_child(_sprite)


## Sets the enemy's tier (1 grunt → goblins, 2 bruiser → the bot). Call after add_child.
func setup_tier(t: int) -> void:
	tier = t
	if t >= 2:
		_speed = BRUISER_SPEED
		_damage = BRUISER_DAMAGE
		_max_hp = BRUISER_HP
		add_to_group("bot_threats")
		if _sprite != null:
			_sprite.texture = ContentLibrary.get_icon("enemy_basic", Vector2i(22, 22), "e08a3a")
	else:
		_speed = SPEED
		_damage = DAMAGE
		_max_hp = MAX_HP
	_hp = _max_hp


func take_damage(amount: int) -> void:
	_hp -= amount
	_flash = 0.12
	if _hp <= 0:
		queue_free()


func _physics_process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	if _sprite != null:
		_sprite.modulate = Color(1, 1, 1) if _flash <= 0.0 else Color(1, 0.75, 0.75)
		_flash = maxf(_flash - delta, 0.0)
	# Tier 1 grunts ONLY ever threaten goblins. Tier 2 bruisers go for the scrapbot, falling back to a
	# goblin in the way only if the bot is somehow gone (so they're never idle).
	var target: Node2D
	if tier >= 2:
		target = _bot()
		if target == null:
			target = _nearest_goblin()
	else:
		target = _nearest_goblin()
	if target == null:
		velocity = Vector2.ZERO  # nothing to attack — hold
		move_and_slide()
		return
	var to := target.global_position - global_position
	if to.length() <= ATTACK_RANGE:
		velocity = Vector2.ZERO
		if _cd <= 0.0 and target.has_method("take_damage"):
			target.take_damage(_damage)
			_cd = ATTACK_CD
	else:
		velocity = to.normalized() * _speed
	move_and_slide()


## The scrapbot (the player) — what tier-2 bruisers attack. Damaging it to 0 is game over.
func _bot() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func _nearest_goblin() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for g: Node in get_tree().get_nodes_in_group("harvester_goblins"):
		if not is_instance_valid(g):
			continue
		var d := global_position.distance_to((g as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = g
	return best
