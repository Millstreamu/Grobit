class_name Room
extends Node2D
## One generated room. Combat rooms lock their doors when Grobit enters, spawn
## enemies, and unlock once the objective (kill all enemies) is met. The
## completion check is factored out so other objective types can be added later.

signal room_cleared(room: Room)
signal room_activated(room: Room)

enum RoomType { START, COMBAT, OBJECTIVE }

const ENEMY_SCENE := preload("res://scenes/enemies/basic_enemy.tscn")

var room_type := RoomType.COMBAT
var interior_rect: Rect2
var doors: Array[Door] = []
var enemy_min := 2
var enemy_max := 4
var enemy_id := "basic_enemy"
var rng := RandomNumberGenerator.new()

var is_cleared := false
var _active := false
var _alive := 0
var _trigger: Area2D


func build_trigger() -> void:
	_trigger = Area2D.new()
	_trigger.collision_mask = 1
	_trigger.monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = interior_rect.size
	shape.shape = rect
	shape.position = interior_rect.get_center()
	_trigger.add_child(shape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)


func center() -> Vector2:
	return interior_rect.get_center()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if room_type == RoomType.START:
		return
	if is_cleared or _active:
		return
	activate()


func activate() -> void:
	_active = true
	for door: Door in doors:
		door.lock()
	var count := rng.randi_range(enemy_min, enemy_max)
	for i in count:
		_spawn_enemy()
	room_activated.emit(self)
	if _alive <= 0:
		_clear()


func _spawn_enemy() -> void:
	var enemy := ENEMY_SCENE.instantiate() as BasicEnemy
	enemy.enemy_id = enemy_id
	var inset := interior_rect.grow(-20.0)
	enemy.global_position = Vector2(
		rng.randf_range(inset.position.x, inset.end.x),
		rng.randf_range(inset.position.y, inset.end.y)
	)
	add_child(enemy)
	_alive += 1
	enemy.tree_exited.connect(_on_enemy_gone)


func _on_enemy_gone() -> void:
	# Ignore teardown (e.g. scene reload) freeing enemies while the room exits.
	if not is_inside_tree():
		return
	_alive -= 1
	if _active and _alive <= 0:
		_clear()


func _clear() -> void:
	is_cleared = true
	_active = false
	for door: Door in doors:
		door.unlock()
	room_cleared.emit(self)
