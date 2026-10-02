extends Node
## Interaction selection respects player facing without regressing the exception
## that lets a pickup in a doorway beat the door and be cleared.
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	var player := Node2D.new(); player.add_to_group("player"); add_child(player); player.global_position = Vector2.ZERO
	var sm := SelectionManager.new(); add_child(sm)
	var door := Door.new(); add_child(door); door.global_position = Vector2(6, 0)   # closer
	var pick := MachinePickup.new(); pick.machine_id = "smelter"; add_child(pick); pick.global_position = Vector2(20, 0)
	await get_tree().process_frame
	pick._in_range = true  # simulate the player overlapping the pickup
	ck(door.can_interact(), "door is in range")
	ck(pick.can_interact(), "pickup is in range")
	var chosen = sm._nearest_interactable()
	ck(chosen == pick, "the pickup is selected over the closer door")
	ck(door.interact_priority() < 0, "door has low interact priority")

	# When candidates are on opposite sides, facing wins before type priority. A
	# junk pile behind Grobit must not steal the door interaction in front.
	player.rotation = PI / 2.0  # Grobit's local up now points right.
	door.global_position = Vector2(20, 0)
	pick._in_range = false
	var pile := ScrapNode.new(); add_child(pile); pile.global_position = Vector2(-20, 0)
	await get_tree().process_frame
	pile._in_range = true
	chosen = sm._nearest_interactable()
	ck(chosen == door, "the door in front is selected over junk behind the player")

	# The doorway escape case remains when both candidates are in front.
	pile._in_range = false
	pick._in_range = true
	pick.global_position = Vector2(22, 0)
	chosen = sm._nearest_interactable()
	ck(chosen == pick, "a pickup in front still beats a door in the same direction")
	if fail == 0: print("DOOR_PICKUP_TEST: ALL PASS")
	else: printerr("DOOR_PICKUP_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
