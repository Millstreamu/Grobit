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
var _held: Node2D  # the scrap pile currently being hold-harvested (if any)


func _ready() -> void:
	_aim = Selector.new()
	_aim.color = Color(1.0, 0.45, 0.45)
	add_child(_aim)
	_aim.clear()

	_interact = Selector.new()
	_interact.color = Color(0.5, 1.0, 0.6)
	add_child(_interact)
	_interact.clear()


func _process(delta: float) -> void:
	_update_aim()
	_update_interactable()
	# Central interaction: F acts on the single nearest in-range interactable, so
	# overlapping interactables never all fire at once. Interactables that define
	# `hold_interact` (scrap piles) are driven continuously while F is held; the rest
	# fire once on press.
	var target := _nearest_interactable()
	if target != null and target.has_method("hold_interact") and Input.is_action_pressed("interact"):
		if _held != target:
			_release_held()
			_held = target
		target.hold_interact(delta)
	else:
		_release_held()
		if Input.is_action_just_pressed("interact") and target != null and target.has_method("interact"):
			target.interact()


func _release_held() -> void:
	if _held != null and is_instance_valid(_held) and _held.has_method("hold_release"):
		_held.hold_release()
	_held = null


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
	return nearest_interactable(player, get_tree().get_nodes_in_group("interactables"))


## Chooses one target for the highlight, prompt, and interaction action. Targets in
## the half-plane the player faces beat targets behind them. Within the same half,
## explicit interaction priority still wins, preserving pickup-over-door behavior
## for items lying in a doorway.
static func nearest_interactable(player: Node2D, interactables: Array[Node]) -> Node2D:
	var best: Node2D
	var best_is_forward := false
	var best_priority := -INF
	var best_distance := INF
	var forward := Vector2.UP.rotated(player.global_rotation)
	for node: Node in interactables:
		if not node is Node2D or not node.has_method("can_interact") or not node.can_interact():
			continue
		var offset := (node as Node2D).global_position - player.global_position
		var is_forward := not offset.is_zero_approx() and forward.dot(offset) > 0.0
		var priority := int(node.interact_priority()) if node.has_method("interact_priority") else 0
		var distance := offset.length()
		if best == null or is_forward and not best_is_forward \
				or is_forward == best_is_forward and (priority > best_priority \
				or priority == best_priority and distance < best_distance):
			best_is_forward = is_forward
			best_priority = priority
			best_distance = distance
			best = node
	return best


func _target_size(node: Node) -> int:
	if node.has_method("selection_size"):
		return int(node.selection_size())
	return 32
