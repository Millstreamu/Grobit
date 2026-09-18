class_name ScrapNode
extends InteractableObject
## Breakdown scrap Grobit harvests for resources — the main resource income. Solid
## and grid-locked. Interact (F) to harvest a charge; finite charges, then spent.
## Yields obey inventory space (a full inventory means you must clear room first).

var yield_table: Array = []
var charges := 3


func _configure() -> void:
	add_to_group("scrap_nodes")
	_sprite_id = "scrap_node"
	_sprite_color = "8a7f6d"
	solid_size = Vector2(26, 26)
	interact_radius = 26.0


func can_interact() -> bool:
	return _in_range and charges > 0


func interaction_prompt() -> String:
	return "[F] Harvest scrap  (%d left)" % charges


func interact() -> void:
	if charges <= 0:
		return
	if not RunState.has_space():
		_notify("Inventory full.")
		return
	for entry: Dictionary in yield_table:
		if randf() > float(entry.get("chance", 1.0)):
			continue
		var amount := randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))
		if amount > 0:
			RunState.add(String(entry.get("resource", "raw_scrap")), amount)
	charges -= 1
	if charges <= 0:
		_sprite.modulate = Color(0.4, 0.4, 0.4)
