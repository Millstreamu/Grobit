class_name FabricatorStation
extends InteractableObject
## An in-room workbench found in a few rooms. Interact (F) to craft transport parts
## (conveyor / splitter / filter) and storage caches from scrap and low-tier items;
## crafted parts go into your stock to place in the factory.


func _configure() -> void:
	add_to_group("fabricators")
	_sprite_id = "fabricator"
	_sprite_color = "c98a3a"
	solid_size = Vector2(30, 30)
	interact_radius = 34.0


func can_interact() -> bool:
	return _in_range


func interaction_prompt() -> String:
	return "[F] Fabricator — craft conveyors, splitters, filters & caches"


func interact() -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_fabricator"):
			hud.open_fabricator()
			return
