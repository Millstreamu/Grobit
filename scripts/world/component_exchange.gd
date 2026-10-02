class_name ComponentExchange
extends InteractableObject
## Where you sell finished components for credit toward a machine. Interact (F) to open
## the exchange: components in your inventory convert to credit, and each full credit bar
## drops a random production machine straight into your inventory (machine_stock).
## Per-run — credit resets when the run ends. Replaces the start-room decode station.

func _configure() -> void:
	add_to_group("component_exchanges")
	_sprite_id = "component_exchange"
	_sprite_color = "e0a93a"
	solid_size = Vector2(30, 30)
	interact_radius = 34.0


func can_interact() -> bool:
	return _in_range


func interaction_prompt() -> String:
	return "[F] Component Exchange — sell components for a machine"


func interact() -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_exchange"):
			hud.open_exchange()
			return
