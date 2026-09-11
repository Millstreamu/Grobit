class_name RespawnBeacon
extends Node2D
## A temporary checkpoint. If Grobit dies, the run controller respawns them at a
## beacon that still has uses, consuming one. When no beacon with uses remains,
## the run ends. Uses are configurable (data/game/buildables).

var buildable_id := "respawn_beacon"
var uses := 2
var _sprite: Sprite2D
var _label: Label


func _ready() -> void:
	add_to_group("respawn_beacons")
	var def: Dictionary = GameData.buildables.get(buildable_id, {})
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon(String(def.get("icon", buildable_id)), Vector2i(24, 24), String(def.get("color", "")))
	add_child(_sprite)
	_label = Label.new()
	_label.position = Vector2(-16, -34)
	add_child(_label)
	_update()


func has_use() -> bool:
	return uses > 0


func consume() -> bool:
	if uses <= 0:
		return false
	uses -= 1
	_update()
	return true


func _update() -> void:
	_label.text = "Beacon x%d" % uses
	_sprite.modulate = Color.WHITE if uses > 0 else Color(0.4, 0.4, 0.4)
