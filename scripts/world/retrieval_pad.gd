class_name RetrievalPad
extends InteractableObject
## Where you ship resources home (Step 4 slice — see docs/SLICE_1_SCOPE.md). Once
## the map objective is done, interacting (F) opens the cartridge loader; sending it
## ends the map and banks the loaded resources toward the Mars total. Pre-placed in
## the (safe) start room for the slice; later this becomes a buildable in any
## cleared room.

func _configure() -> void:
	add_to_group("retrieval_pads")
	_sprite_id = "retrieval_pad"
	_sprite_color = "6ca0e0"
	solid_size = Vector2(30, 30)
	interact_radius = 36.0


func can_interact() -> bool:
	return _in_range


func interaction_prompt() -> String:
	if RunState.shipping_unlocked:
		return "[F] Retrieval Pad — load a cartridge and ship out"
	return "[F] Retrieval Pad — complete the objective to enable shipping"


func interact() -> void:
	if not RunState.shipping_unlocked:
		_notify("Complete the map objective to bring shipping online.")
		return
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_cartridge"):
			hud.open_cartridge()
			return
