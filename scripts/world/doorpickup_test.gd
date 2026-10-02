extends Node
## A pickup in a doorway must be selectable over the door (doors are low priority),
## so an item blocking a door can be cleared.
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
	if fail == 0: print("DOOR_PICKUP_TEST: ALL PASS")
	else: printerr("DOOR_PICKUP_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
