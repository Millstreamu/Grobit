class_name PowerRelay
extends Node2D
## A world buildable (not a factory machine): once placed, it powers the room it sits
## in, turning that room's lights on (see LightingSystem.light_room). Cheap/free for
## now — a quick way to reveal a room without relying on the vision cone.

var buildable_id := "power_relay"
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("power_relays")
	var def: Dictionary = GameData.buildables.get(buildable_id, {})
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon(String(def.get("icon", buildable_id)), Vector2i(24, 24), String(def.get("color", "")))
	add_child(_sprite)
	# Position is set by the BuildManager before we're added, so light the room now.
	_power_on()


func _power_on() -> void:
	var run := get_tree().get_first_node_in_group("run_controller")
	if run == null:
		return
	var generator: AreaGenerator = run.get("generator")
	var lighting := get_tree().get_first_node_in_group("lighting_system") as LightingSystem
	if generator == null or lighting == null:
		return
	var room := generator.room_at(global_position)
	if room != null:
		lighting.light_room(room.interior_tiles)
