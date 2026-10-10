class_name SystemTerminal
extends InteractableObject
## A link back to the goblin base, found out in the map. Interact (F) to open the LAIR WINDOW —
## three tabs: the Production workshop floor, the Goblins roster (recruit / tools / memorial), and
## Tasks (colony quests, permanent upgrades & tech, and the lair-restoration goal).

func _configure() -> void:
	add_to_group("system_terminals")
	_sprite_id = "system_terminal"
	_sprite_color = "5aa9e6"
	solid_size = Vector2(30, 30)
	interact_radius = 34.0


func can_interact() -> bool:
	return _in_range


func interaction_prompt() -> String:
	return "[F] System Terminal — workshop, goblins & tasks"


func interact() -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_terminal"):
			hud.open_terminal()
			return
