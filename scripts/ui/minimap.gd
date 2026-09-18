class_name Minimap
extends Control
## Small explored-area map. Draws each generated room as a coloured cell laid out
## by its grid slot, with connection lines, the current room highlighted, and the
## Power Generator marked. Colours encode room type / cleared state.

const CELL := 14.0   # pixels per cell-grid unit
const BOX := 10.0    # room marker size
const MARGIN := Vector2(10, 22)

var _rooms: Array[Room] = []
var _edges: Array = []
var _generator: AreaGenerator


func configure(generator: AreaGenerator) -> void:
	_generator = generator
	_rooms = generator.rooms
	_edges = generator.room_edges
	queue_redraw()


func _process(_delta: float) -> void:
	if not _rooms.is_empty():
		queue_redraw()


func _draw() -> void:
	if _rooms.is_empty():
		return
	var min_p := _rooms[0].map_position
	var max_p := _rooms[0].map_position
	for room: Room in _rooms:
		min_p = min_p.min(room.map_position)
		max_p = max_p.max(room.map_position)

	var span := max_p - min_p
	var bg_size := Vector2((span.x + 1) * CELL + MARGIN.x, (span.y + 1) * CELL + MARGIN.y) + MARGIN
	draw_rect(Rect2(Vector2.ZERO, bg_size), Color(0.05, 0.05, 0.08, 0.8))
	draw_string(get_theme_default_font(), Vector2(MARGIN.x, 15), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.85))

	# Connections underneath the room markers.
	for edge: Array in _edges:
		draw_line(_pos_to_local(edge[0], min_p), _pos_to_local(edge[1], min_p), Color(0.5, 0.5, 0.55), 1.5)

	var current := _current_room()
	for room: Room in _rooms:
		var pos := _pos_to_local(room.map_position, min_p)
		var rect := Rect2(pos - Vector2(BOX, BOX) * 0.5, Vector2(BOX, BOX))
		draw_rect(rect, _room_color(room))
		if room == current:
			draw_rect(rect.grow(1.5), Color.WHITE, false, 1.5)


func _pos_to_local(p: Vector2, min_p: Vector2) -> Vector2:
	return MARGIN + (p - min_p) * CELL + Vector2(BOX, BOX) * 0.5


func _current_room() -> Room:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return null
	var nearest: Room
	var nearest_distance := INF
	for room: Room in _rooms:
		var distance := room.center().distance_to(player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = room
	return nearest


func _room_color(room: Room) -> Color:
	match room.room_type:
		Room.RoomType.START:
			return Color(0.40, 0.60, 1.00)
		Room.RoomType.OBJECTIVE:
			return Color(0.45, 0.85, 0.5) if _objective_repaired() else Color(0.95, 0.80, 0.30)
		Room.RoomType.SALVAGE:
			return Color(0.30, 0.80, 0.80)
		Room.RoomType.HAZARD:
			return Color(0.90, 0.50, 0.30) if not room.is_cleared else Color(0.45, 0.70, 0.45)
		Room.RoomType.SPAWNER:
			return Color(0.70, 0.40, 0.90)
		Room.RoomType.WORKSHOP:
			return Color(0.85, 0.85, 0.55)
		_:  # COMBAT
			return Color(0.45, 0.80, 0.45) if room.is_cleared else Color(0.55, 0.55, 0.60)


func _objective_repaired() -> bool:
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		if node is PowerGenerator:
			return (node as PowerGenerator).is_repaired
	return false
