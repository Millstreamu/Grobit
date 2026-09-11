class_name BuildManager
extends Node2D
## Very simple build mode. Toggle it, pick a buildable, and a ghost preview
## follows the cursor. Placement is allowed only on valid ground near Grobit and
## costs resources. Only two buildables exist in the prototype.

signal state_changed(active: bool)
signal message(text: String)

@export var build_range := 220.0
@export var tile := 32

var _active := false
var _buildable_ids: Array[String] = []
var _selected := 0
var _preview: Sprite2D


func _ready() -> void:
	add_to_group("build_manager")
	_buildable_ids.assign(GameData.buildables.keys())
	_preview = Sprite2D.new()
	_preview.modulate = Color(1, 1, 1, 0.6)
	_preview.z_index = 5
	_preview.visible = false
	add_child(_preview)
	_refresh_preview_texture()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_build"):
		_set_active(not _active)
	if not _active:
		return
	if Input.is_action_just_pressed("build_cancel"):
		_set_active(false)
		return
	if Input.is_action_just_pressed("hotbar_1"):
		_select(0)
	if Input.is_action_just_pressed("hotbar_2"):
		_select(1)

	var pos := _snapped_target()
	_preview.global_position = pos
	var ok := _is_valid(pos) and RunState.can_afford(_current_cost())
	_preview.modulate = Color(0.4, 1, 0.4, 0.6) if ok else Color(1, 0.4, 0.4, 0.6)

	if Input.is_action_just_pressed("attack"):
		_try_place(pos)


func is_build_active() -> bool:
	return _active


func selected_buildable() -> String:
	if _buildable_ids.is_empty():
		return ""
	return _buildable_ids[_selected]


func status_line() -> String:
	if not _active:
		return ""
	var id := selected_buildable()
	var def: Dictionary = GameData.buildables.get(id, {})
	return "BUILD: %s  (%s)   [1/2] select   [LMB] place   [B/Esc] exit" % [
		String(def.get("name", id)), _cost_text(_current_cost())
	]


func _set_active(value: bool) -> void:
	_active = value
	_preview.visible = value
	if value:
		_refresh_preview_texture()
	state_changed.emit(_active)


func _select(index: int) -> void:
	if index < 0 or index >= _buildable_ids.size():
		return
	_selected = index
	_refresh_preview_texture()


func _refresh_preview_texture() -> void:
	var def: Dictionary = GameData.buildables.get(selected_buildable(), {})
	_preview.texture = ContentLibrary.get_icon(String(def.get("icon", selected_buildable())), Vector2i(28, 28), String(def.get("color", "")))


func _current_cost() -> Dictionary:
	return GameData.buildables.get(selected_buildable(), {}).get("cost", {})


func _snapped_target() -> Vector2:
	var mouse := get_global_mouse_position()
	return Vector2(floorf(mouse.x / tile) * tile + tile * 0.5, floorf(mouse.y / tile) * tile + tile * 0.5)


func _is_valid(pos: Vector2) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or player.global_position.distance_to(pos) > build_range:
		return false
	var space := get_viewport().get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	query.shape = circle
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = 1
	if player is CollisionObject2D:
		query.exclude = [player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()


func _try_place(pos: Vector2) -> void:
	var id := selected_buildable()
	if not _is_valid(pos):
		message.emit("Can't build there.")
		return
	var cost := _current_cost()
	if not RunState.spend(cost):
		message.emit("Not enough resources for %s." % GameData.buildables.get(id, {}).get("name", id))
		return
	var node := _instantiate_buildable(id)
	if node == null:
		return
	node.global_position = pos
	get_parent().add_child(node)
	message.emit("Built %s." % GameData.buildables.get(id, {}).get("name", id))


func _instantiate_buildable(id: String) -> Node2D:
	match id:
		"respawn_beacon":
			var beacon := RespawnBeacon.new()
			beacon.buildable_id = id
			beacon.uses = int(GameData.buildables.get(id, {}).get("uses", 2))
			return beacon
		"extraction_beacon":
			var beacon := ExtractionBeacon.new()
			beacon.buildable_id = id
			# The run controller connects to this to end the run.
			for controller: Node in get_tree().get_nodes_in_group("run_controller"):
				if controller.has_method("on_extraction_confirmed"):
					beacon.extract_confirmed.connect(controller.on_extraction_confirmed)
			return beacon
	push_error("BuildManager has no buildable named '%s'." % id)
	return null


func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for res: String in cost:
		parts.append("%d %s" % [int(cost[res]), GameData.resource_name(res)])
	return ", ".join(parts)
