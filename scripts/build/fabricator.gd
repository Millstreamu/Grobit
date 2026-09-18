class_name Fabricator
extends InteractableObject
## A crafting machine you build in a room. Manufacturing components requires one:
## interact (F) with a built Fabricator to open the manufacturing screen. This is
## the first "build machines in a room to craft" step; more machine types (e.g. an
## Assembler unlocking advanced recipes) can follow the same pattern.

var buildable_id := "fabricator"


func _configure() -> void:
	add_to_group("fabricators")
	var def: Dictionary = GameData.buildables.get(buildable_id, {})
	_sprite_id = String(def.get("icon", "fabricator"))
	_sprite_color = String(def.get("color", "4f7fae"))
	solid_size = Vector2(30, 30)
	interact_radius = 30.0


func interaction_prompt() -> String:
	return "[F] Fabricator — manufacture components"


func interact() -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_manufacture"):
			hud.open_manufacture()
