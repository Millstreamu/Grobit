class_name ToolPickup
extends Area2D
## A scrap TOOL lying in a room. Walk over it and [F] to take it — it goes to the colony's tool
## pool (MetaState.tools_found), to be equipped onto a goblin back at the System Terminal. Tools
## gate what scrap a goblin can strip (their tier), so a better tool is the main progression find.
## Non-solid, so the bot/goblins walk over it.

var tool_id := "copper_cutter"

var _in_range := false
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("pickups")
	var tier := MetaState.tool_tier(tool_id)
	var tints := ["c9a24a", "b0632a", "359186", "c4bba2"]
	var tint: String = tints[clampi(tier - 1, 0, 3)]
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon("tool", Vector2i(22, 22), tint)
	add_child(_sprite)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 13.0
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = false


func can_interact() -> bool:
	return _in_range


func selection_size() -> int:
	return 22


func interaction_prompt() -> String:
	return "[F] Take %s (tier %d tool)" % [MetaState.tool_name(tool_id), MetaState.tool_tier(tool_id)]


func interact() -> void:
	MetaState.found_tool(tool_id)
	queue_free()
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("log_message"):
			hud.log_message("Found a %s (tier %d tool) — equip it to a goblin at the System Terminal." % [MetaState.tool_name(tool_id), MetaState.tool_tier(tool_id)])
			return
