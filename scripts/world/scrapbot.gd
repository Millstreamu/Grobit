class_name Scrapbot
extends InteractableObject
## The goblin's scrapbot, parked at the edge of the lair. [F] to hop in and drive out into
## the ruins (begins the run). When you return, [F] again to climb out and head home
## (extract). Non-solid so you can stand next to / on it. Behaviour lives in RunController.

func _configure() -> void:
	add_to_group("scrapbots")
	_sprite_id = "scrapbot"
	_sprite_color = "9ad06a"
	solid_size = Vector2(30, 30)
	interact_radius = 36.0


func _post_setup() -> void:
	collision_layer = 0  # non-solid — the goblin can walk right up to it


func can_interact() -> bool:
	return _in_range


func interaction_prompt() -> String:
	if RunState.driving:
		return "[F] Climb out & head home (extract)"
	return "[F] Set up your loadout & launch"


func interact() -> void:
	for controller: Node in get_tree().get_nodes_in_group("run_controller"):
		if controller.has_method("on_scrapbot_interact"):
			controller.on_scrapbot_interact()
			return
