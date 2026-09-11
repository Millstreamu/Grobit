class_name ExtractionBeacon
extends Area2D
## Lets the player end the current run successfully, keeping what they carry.
## Interacting once arms it; interacting again confirms extraction.

signal extract_confirmed()

@export var interact_radius := 40.0

var buildable_id := "extraction_beacon"
var _in_range := false
var _armed := false
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("extraction_beacons")
	collision_mask = 1
	monitoring = true
	var def: Dictionary = GameData.buildables.get(buildable_id, {})
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon(String(def.get("icon", buildable_id)), Vector2i(28, 28), String(def.get("color", "")))
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
		_in_range = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = false
		_armed = false


func _process(_delta: float) -> void:
	if not _in_range:
		return
	if Input.is_action_just_pressed("interact"):
		if not _armed:
			_armed = true
		else:
			extract_confirmed.emit()


func can_interact() -> bool:
	return _in_range


func interaction_prompt() -> String:
	if _armed:
		return "[F] Confirm extraction — end run and keep resources"
	return "[F] Extraction Beacon — leave the area"
