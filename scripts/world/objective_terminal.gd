class_name ObjectiveTerminal
extends InteractableObject
## The map's objective (Step 4 slice — see docs/SLICE_1_SCOPE.md). Activating it (F)
## brings shipping online: it unlocks the retrieval pad so resources can be sent
## home. A single, simple gate for the slice; richer per-map objectives come later.

var _done := false


func _configure() -> void:
	add_to_group("objective_terminals")
	_sprite_id = "objective_terminal"
	_sprite_color = "e0c14a"
	solid_size = Vector2(30, 30)
	interact_radius = 34.0


func can_interact() -> bool:
	return _in_range and not _done


func interaction_prompt() -> String:
	return "[F] Activate objective — bring shipping online"


func interact() -> void:
	if _done:
		return
	_done = true
	RunState.unlock_shipping()
	if _sprite != null:
		_sprite.modulate = Color(0.5, 1.0, 0.6)
	_notify("Objective complete — shipping online. Return to the Retrieval Pad to ship out.")
