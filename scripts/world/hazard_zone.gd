class_name HazardZone
extends Area2D
## An environmental hazard that damages the player at a fixed interval while they
## stand inside it. Used by hazard rooms. Balance values are set on creation.

var damage := 1
var interval := 0.6
var radius := 40.0

var _player_inside := false
var _timer := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	collision_mask = 1
	monitoring = true
	# A translucent red disc marks the danger area.
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon("hazard_zone", Vector2i(int(radius * 2), int(radius * 2)), "cc3333")
	_sprite.modulate = Color(1, 1, 1, 0.35)
	_sprite.z_index = -1
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if not _player_inside:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval
		var player := get_tree().get_first_node_in_group("player")
		if player != null and player.has_method("take_damage"):
			player.take_damage(damage)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_timer = interval


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
