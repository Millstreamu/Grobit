extends Node
## Doors start closed, toggle with F when the player is near (but not on the tile), and
## a room combat-seal (lock/unlock) overrides manual control.
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	var player := Node2D.new(); player.add_to_group("player"); player.global_position = Vector2(200, 0); add_child(player)
	var d := Door.new(); add_child(d); d.global_position = Vector2(0, 0)
	await get_tree().process_frame
	ck(d._solid(), "door starts closed (solid)")
	ck(not d.can_interact(), "far player can't interact")
	player.global_position = Vector2(10, 0)  # within interact_radius
	ck(d.can_interact(), "nearby player can interact")
	ck(d.interaction_prompt() == "[F] Open door", "prompt shows Open when closed")
	# can't close a door while standing on it (distance < 22)
	d.interact()  # opens (player at 10px: opening allowed)
	ck(not d._solid(), "F opened the door")
	ck(d.interaction_prompt() == "[F] Close door", "prompt shows Close when open")
	d.interact()  # try to close while at 10px -> refused
	ck(not d._solid(), "won't close on top of the player")
	player.global_position = Vector2(28, 0)  # step back but still in range
	d.interact()  # now closes
	ck(d._solid(), "closes once player steps off the tile")
	# combat seal blocks manual toggle
	d.lock()
	ck(d._solid() and not d.can_interact(), "sealed door is solid and non-interactable")
	d.interact()  # no effect while sealed
	ck(d._solid(), "F does nothing while sealed")
	d.unlock()
	ck(not d._solid() and d.can_interact(), "unlock opens it and restores F")
	if fail == 0: print("DOOR CHECKS PASS")
	else: printerr(fail, " FAIL")
	get_tree().quit(fail)
