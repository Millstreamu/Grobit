class_name DecodeStation
extends InteractableObject
## Where you draft modules (see docs/INVENTORY_FACTORY_DIRECTION.md). Interact (F) to
## spend Tech Data and pick 1 of 3 modules, which join your permanent collection.

const COST := {"tech_data": 1}


func _configure() -> void:
	add_to_group("decode_stations")
	_sprite_id = "decode_station"
	_sprite_color = "8a5ae0"
	solid_size = Vector2(30, 30)
	interact_radius = 34.0


func can_interact() -> bool:
	return _in_range


func interaction_prompt() -> String:
	return "[F] Decode Station — spend %d Tech Data to draft a module" % int(COST["tech_data"])


func interact() -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_decode"):
			hud.open_decode(COST)
			return
