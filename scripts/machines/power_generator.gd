class_name PowerGenerator
extends Area2D
## The area's major broken machine (prototype objective). Grobit brings
## manufactured components here and interacts to deposit them. Once every
## required component is delivered, the generator is repaired and the area is
## complete. Requirements are data-driven (area.objective.requires).

signal repaired()

@export var interact_radius := 44.0

var requires: Dictionary = {}
var delivered: Dictionary = {}
var is_repaired := false
var _player_in_range := false
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactables")
	collision_mask = 1
	monitoring = true
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon("power_generator", Vector2i(48, 48), "d0563a")
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = interact_radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func _process(_delta: float) -> void:
	if is_repaired or not _player_in_range:
		return
	if Input.is_action_just_pressed("interact"):
		_deposit()


func can_interact() -> bool:
	return _player_in_range and not is_repaired


func interaction_prompt() -> String:
	if is_repaired:
		return "Power Generator: REPAIRED"
	var parts: Array = []
	for res: String in requires:
		parts.append("%s %d/%d" % [GameData.resource_name(res), int(delivered.get(res, 0)), int(requires[res])])
	return "[F] Repair Power Generator — " + ", ".join(parts)


func _deposit() -> void:
	for res: String in requires:
		var need := int(requires[res]) - int(delivered.get(res, 0))
		if need <= 0:
			continue
		var give := mini(need, RunState.get_quantity(res))
		if give > 0:
			RunState.add(res, -give)
			delivered[res] = int(delivered.get(res, 0)) + give
	if _is_complete():
		is_repaired = true
		_sprite.modulate = Color(0.6, 1.0, 0.6)
		repaired.emit()


func _is_complete() -> bool:
	for res: String in requires:
		if int(delivered.get(res, 0)) < int(requires[res]):
			return false
	return true
