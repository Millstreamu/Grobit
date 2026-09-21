class_name BuildManager
extends Node2D
## Very simple, fully keyboard-driven build mode. Toggle it, pick a buildable, and
## a grid cursor (moved with WASD, while Grobit holds still) shows a ghost preview.
## Placement is allowed only on valid ground near Grobit and costs resources.

signal state_changed(active: bool)
signal message(text: String)

@export var build_range := 220.0
@export var tile := 32

var _active := false
var _buildable_ids: Array[String] = []
var _selected := 0
var _preview: Sprite2D
var _selector: Selector
var _cursor_tile := Vector2i.ZERO
# Last frame's placement checks, so the build palette can explain why a spot is
# (in)valid without recomputing the physics query.
var _valid_here := false
var _affordable := false


func _ready() -> void:
	add_to_group("build_manager")
	_buildable_ids.assign(GameData.buildables.keys())
	_preview = Sprite2D.new()
	_preview.modulate = Color(1, 1, 1, 0.6)
	_preview.z_index = 5
	_preview.visible = false
	add_child(_preview)
	_selector = Selector.new()
	_selector.pulse = false  # steady bracket; colour conveys valid/invalid
	add_child(_selector)
	_selector.clear()
	_refresh_preview_texture()
	# Debug hook (env-gated): open build mode with a little stock so the palette can
	# be inspected/screenshotted in headless or windowed runs.
	if OS.has_environment("GROBIT_OPEN_BUILD"):
		RunState.add("scrap_metal", 4)
		_set_active.call_deferred(true)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_build"):
		_set_active(not _active)
	if not _active:
		return
	if Input.is_action_just_pressed("build_cancel"):
		_set_active(false)
		return
	for i in mini(4, _buildable_ids.size()):
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			_select(i)
	if Input.is_action_just_pressed("cycle_target") and not _buildable_ids.is_empty():
		_select((_selected + 1) % _buildable_ids.size())

	_move_cursor()
	var pos := _tile_center(_cursor_tile)
	_preview.global_position = pos
	_valid_here = _is_valid(pos)
	_affordable = RunState.can_afford(_current_cost())
	var ok := _valid_here and _affordable
	_preview.modulate = Color(0.4, 1, 0.4, 0.6) if ok else Color(1, 0.4, 0.4, 0.6)
	_selector.highlight(pos, 32)
	_selector.set_color(Color(0.4, 1, 0.4) if ok else Color(1, 0.4, 0.4))

	if Input.is_action_just_pressed("attack"):
		_try_place(pos)


func is_build_active() -> bool:
	return _active


func selected_buildable() -> String:
	if _buildable_ids.is_empty():
		return ""
	return _buildable_ids[_selected]


## Read by the build palette UI.
func buildable_ids() -> Array[String]:
	return _buildable_ids


func selected_index() -> int:
	return _selected


## "" when the current cursor tile is a legal, affordable placement; otherwise a
## short reason the palette shows in red (position problems take priority).
func placement_reason() -> String:
	if not _active:
		return ""
	if not _valid_here:
		return "Can't build there"
	if not _affordable:
		return "Not enough resources"
	return ""


func _set_active(value: bool) -> void:
	_active = value
	_preview.visible = value
	if value:
		_refresh_preview_texture()
		_reset_cursor()
	else:
		_selector.clear()
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


func _tile_center(tile_coord: Vector2i) -> Vector2:
	return Vector2(tile_coord.x * tile + tile * 0.5, tile_coord.y * tile + tile * 0.5)


func _world_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / tile), floori(world_position.y / tile))


# Places the cursor on the tile just in front of Grobit when build mode opens.
func _reset_cursor() -> void:
	var player := get_tree().get_first_node_in_group("player") as GrobitPlayer
	if player == null:
		_cursor_tile = Vector2i.ZERO
		return
	var facing := player.facing_direction()
	var step := Vector2i(roundi(facing.x), roundi(facing.y))
	if step == Vector2i.ZERO:
		step = Vector2i(0, -1)
	_cursor_tile = _world_to_tile(player.global_position) + step


# One tile per key press (precise); ignores steps that would leave build range.
func _move_cursor() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var step := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"):
		step.y -= 1
	if Input.is_action_just_pressed("move_down"):
		step.y += 1
	if Input.is_action_just_pressed("move_left"):
		step.x -= 1
	if Input.is_action_just_pressed("move_right"):
		step.x += 1
	if step == Vector2i.ZERO:
		return
	var candidate := _cursor_tile + step
	if player.global_position.distance_to(_tile_center(candidate)) <= build_range:
		_cursor_tile = candidate


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
	push_error("BuildManager has no buildable named '%s'." % id)
	return null
