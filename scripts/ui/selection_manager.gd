class_name SelectionManager
extends Node2D
## Drives the world-space selection highlights during a run using pooled
## `Selector` brackets. Keeps selection visuals in one place so more can be added
## (e.g. a future target picker) without scattering highlight code.
##
## Highlights maintained here:
## - aim target: the enemy the auto-attack is currently pointed at.
## - interactable: the nearest in-range interactable (generator / extraction beacon).
## The build placement tile is highlighted by BuildManager itself, since it already
## owns the placement cursor.

var _aim: Selector
var _interact: Selector


func _ready() -> void:
	_aim = Selector.new()
	_aim.color = Color(1.0, 0.45, 0.45)
	add_child(_aim)
	_aim.clear()

	_interact = Selector.new()
	_interact.color = Color(0.5, 1.0, 0.6)
	add_child(_interact)
	_interact.clear()


func _process(_delta: float) -> void:
	_update_aim()
	_update_interactable()
	# Central interaction: F acts on the single nearest in-range interactable, so
	# overlapping interactables never all fire at once.
	if Input.is_action_just_pressed("interact"):
		var target := _nearest_interactable()
		if target != null and target.has_method("interact"):
			target.interact()


func _update_aim() -> void:
	var player := get_tree().get_first_node_in_group("player") as GrobitPlayer
	if player == null or player.combat == null:
		_aim.clear()
		return
	var target := player.combat.get_aim_target()
	if target == null:
		_aim.clear()
	else:
		_aim.highlight(target.global_position, _target_size(target))


func _update_interactable() -> void:
	var nearest := _nearest_interactable()
	if nearest != null:
		_interact.highlight(nearest.global_position, _target_size(nearest))
	else:
		_interact.clear()


func _nearest_interactable() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return null
	var best: Node2D
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		if not node is Node2D or not node.has_method("can_interact") or not node.can_interact():
			continue
		var distance := player.global_position.distance_to((node as Node2D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func _target_size(node: Node) -> int:
	if node.has_method("selection_size"):
		return int(node.selection_size())
	return 32
