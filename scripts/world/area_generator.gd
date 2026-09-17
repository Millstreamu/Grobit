class_name AreaGenerator
extends Node2D
## Rough seeded generator. Produces a set of connected rectangular rooms joined
## by short corridors, with doors at each opening. Deliberately simple: rooms sit
## on a grid and are connected by a randomized spanning tree, so every room is
## reachable and no unreachable space is created. Room shapes can become organic
## later without changing the room/door/run contracts.

const ROOM_W := 12
const ROOM_H := 10
const CORRIDOR := 3

const DIRS := {
	"N": Vector2i(0, -1),
	"E": Vector2i(1, 0),
	"S": Vector2i(0, 1),
	"W": Vector2i(-1, 0),
}
const OPPOSITE := {"N": "S", "S": "N", "E": "W", "W": "E"}

var tile := 32
var _floor_tile := "floor_clean"
var _wall_tile := "wall"

var _tiles: Dictionary = {}          # Vector2i -> "floor" | "wall"
var _floors: Node2D
var _wall_sprites: Node2D
var _walls: StaticBody2D
var _doors_root: Node2D

var rooms: Array[Room] = []
var room_edges: Array = []  # slot pairs, for the minimap connection lines
var start_position := Vector2.ZERO
var objective_room: Room


## Builds the whole area. Returns start_position for the player.
func build(area_id: String, run_seed: int) -> Vector2:
	var area: Dictionary = GameData.area(area_id)
	_floor_tile = String(area.get("floor_tile", "floor_clean"))
	_wall_tile = String(area.get("wall_tile", "wall"))
	if ContentLibrary.tileset.tile_width > 0:
		tile = ContentLibrary.tileset.tile_width

	_floors = _make_container("Floors", -2)
	_wall_sprites = _make_container("WallSprites", -1)
	_walls = StaticBody2D.new()
	_walls.name = "Walls"
	add_child(_walls)
	_doors_root = _make_container("Doors", -1)

	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed

	var generation: Dictionary = area.get("generation", {})
	var room_count := maxi(2, int(generation.get("room_count", 6)))
	var enemy_min := int(generation.get("min_enemies", 2))
	var enemy_max := int(generation.get("max_enemies", 4))
	var enemy_id := "basic_enemy"
	if area.get("enemies", []) is Array and not area.enemies.is_empty():
		enemy_id = String(area.enemies[0])
	var weights: Dictionary = generation.get("room_type_weights", {"combat": 1})
	var enemy_weights: Dictionary = area.get("enemy_weights", {})
	var salvage_loot: Array = area.get("salvage_loot", [])
	var hazard_config: Dictionary = area.get("hazard", {})
	var spawner_config: Dictionary = area.get("spawner", {})

	var layout := _generate_layout(rng, room_count)
	var slots: Array = layout.slots
	var edges: Array = layout.edges
	var open_sides: Dictionary = layout.open_sides
	var start_slot: Vector2i = slots[0]
	var objective_slot: Vector2i = _farthest_slot(slots, edges, start_slot)
	room_edges = edges

	# Corridors first so room openings render on top of corridor floor.
	for edge: Array in edges:
		_build_corridor(edge[0], edge[1])

	for slot: Vector2i in slots:
		var type := Room.RoomType.COMBAT
		if slot == start_slot:
			type = Room.RoomType.START
		elif slot == objective_slot:
			type = Room.RoomType.OBJECTIVE
		else:
			type = _pick_room_type(weights, rng)
		var room := _build_room(slot, open_sides.get(slot, []), type, run_seed, enemy_min, enemy_max, enemy_id)
		room.enemy_weights = enemy_weights
		room.salvage_loot = salvage_loot
		room.hazard_config = hazard_config
		rooms.append(room)
		if type == Room.RoomType.START:
			start_position = room.center()
		elif type == Room.RoomType.OBJECTIVE:
			objective_room = room

	_render_tiles()
	for room: Room in rooms:
		room.build_trigger()
		_populate_room(room, spawner_config, enemy_id)
	return start_position


func _pick_room_type(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0
	for key: String in weights:
		total += int(weights[key])
	if total <= 0:
		return Room.RoomType.COMBAT
	var roll := rng.randi_range(1, total)
	var acc := 0
	for key: String in weights:
		acc += int(weights[key])
		if roll <= acc:
			return _type_from_string(key)
	return Room.RoomType.COMBAT


func _type_from_string(name: String) -> int:
	match name:
		"salvage": return Room.RoomType.SALVAGE
		"hazard": return Room.RoomType.HAZARD
		"spawner": return Room.RoomType.SPAWNER
	return Room.RoomType.COMBAT


func _populate_room(room: Room, spawner_config: Dictionary, enemy_id: String) -> void:
	match room.room_type:
		Room.RoomType.SALVAGE:
			room.spawn_salvage()
		Room.RoomType.HAZARD:
			room.spawn_hazard()
		Room.RoomType.SPAWNER:
			_add_spawners(room, spawner_config, enemy_id)


func _add_spawners(room: Room, config: Dictionary, _enemy_id: String) -> void:
	room.spawner_config = config
	var markers := maxi(1, int(config.get("markers", 1)))
	var origin := _slot_origin(room.slot)
	for i in markers:
		var spawner := Spawner.new()
		room.add_child(spawner)
		# Mount on the top interior row, spread horizontally, clear of the centre door.
		var tx := origin.x + 2 + i * 3
		var ty := origin.y + 1
		spawner.global_position = Vector2(tx * tile + tile * 0.5, ty * tile + tile * 0.5)
		room.spawners.append(spawner)


# ---------------------------------------------------------------- layout ----

func _generate_layout(rng: RandomNumberGenerator, room_count: int) -> Dictionary:
	var slots: Array = [Vector2i.ZERO]
	var occupied := {Vector2i.ZERO: true}
	var edges: Array = []
	var open_sides := {Vector2i.ZERO: []}
	var attempts := 0
	var max_attempts := room_count * 200

	while slots.size() < room_count and attempts < max_attempts:
		attempts += 1
		var base: Vector2i = slots[rng.randi_range(0, slots.size() - 1)]
		var dir_names: Array = DIRS.keys()
		_shuffle(dir_names, rng)
		for side: String in dir_names:
			var neighbor: Vector2i = base + DIRS[side]
			if occupied.has(neighbor):
				continue
			occupied[neighbor] = true
			slots.append(neighbor)
			open_sides[neighbor] = []
			edges.append([base, neighbor])
			(open_sides[base] as Array).append(side)
			(open_sides[neighbor] as Array).append(OPPOSITE[side])
			break

	return {"slots": slots, "edges": edges, "open_sides": open_sides}


func _farthest_slot(slots: Array, edges: Array, from: Vector2i) -> Vector2i:
	var adjacency := {}
	for slot: Vector2i in slots:
		adjacency[slot] = []
	for edge: Array in edges:
		(adjacency[edge[0]] as Array).append(edge[1])
		(adjacency[edge[1]] as Array).append(edge[0])
	var distance := {from: 0}
	var queue: Array = [from]
	var farthest := from
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for next: Vector2i in adjacency[current]:
			if distance.has(next):
				continue
			distance[next] = int(distance[current]) + 1
			if distance[next] > int(distance[farthest]):
				farthest = next
			queue.append(next)
	return farthest


# ------------------------------------------------------------ room build ----

func _slot_origin(slot: Vector2i) -> Vector2i:
	return Vector2i(slot.x * (ROOM_W + CORRIDOR), slot.y * (ROOM_H + CORRIDOR))


func _build_room(slot: Vector2i, open_sides: Array, type: int, run_seed: int, enemy_min: int, enemy_max: int, enemy_id: String) -> Room:
	var origin := _slot_origin(slot)
	var mid_row := ROOM_H / 2
	var mid_col := ROOM_W / 2

	for ry in ROOM_H:
		for rx in ROOM_W:
			var pos := Vector2i(origin.x + rx, origin.y + ry)
			var is_border := rx == 0 or ry == 0 or rx == ROOM_W - 1 or ry == ROOM_H - 1
			var is_opening := false
			if rx == ROOM_W - 1 and ry == mid_row and open_sides.has("E"):
				is_opening = true
			elif rx == 0 and ry == mid_row and open_sides.has("W"):
				is_opening = true
			elif ry == 0 and rx == mid_col and open_sides.has("N"):
				is_opening = true
			elif ry == ROOM_H - 1 and rx == mid_col and open_sides.has("S"):
				is_opening = true
			if is_border and not is_opening:
				_set_tile(pos, "wall")
			else:
				_set_tile(pos, "floor")

	var room := Room.new()
	room.name = "Room_%d_%d" % [slot.x, slot.y]
	room.room_type = type
	room.slot = slot
	room.interior_rect = Rect2(
		Vector2((origin.x + 1) * tile, (origin.y + 1) * tile),
		Vector2((ROOM_W - 2) * tile, (ROOM_H - 2) * tile)
	)
	room.enemy_id = enemy_id
	# Start/salvage/spawner rooms have no on-entry enemy wave.
	if type == Room.RoomType.START or type == Room.RoomType.SALVAGE or type == Room.RoomType.SPAWNER:
		room.enemy_min = 0
		room.enemy_max = 0
	else:
		room.enemy_min = enemy_min
		room.enemy_max = enemy_max
	room.rng.seed = run_seed ^ (slot.x * 73856093) ^ (slot.y * 19349663)
	add_child(room)

	for side: String in open_sides:
		var door := Door.new()
		_doors_root.add_child(door)
		door.global_position = _door_world_position(origin, side, mid_row, mid_col)
		room.doors.append(door)
	return room


func _door_world_position(origin: Vector2i, side: String, mid_row: int, mid_col: int) -> Vector2:
	var tx := origin.x
	var ty := origin.y
	match side:
		"E":
			tx = origin.x + ROOM_W - 1
			ty = origin.y + mid_row
		"W":
			tx = origin.x
			ty = origin.y + mid_row
		"N":
			tx = origin.x + mid_col
			ty = origin.y
		"S":
			tx = origin.x + mid_col
			ty = origin.y + ROOM_H - 1
	return Vector2(tx * tile + tile * 0.5, ty * tile + tile * 0.5)


func _build_corridor(a: Vector2i, b: Vector2i) -> void:
	var mid_row := ROOM_H / 2
	var mid_col := ROOM_W / 2
	if a.x != b.x:
		var west: Vector2i = a if a.x < b.x else b
		var origin := _slot_origin(west)
		var row := origin.y + mid_row
		var start_col := origin.x + ROOM_W
		for k in CORRIDOR:
			_set_tile(Vector2i(start_col + k, row), "floor")
			_set_tile(Vector2i(start_col + k, row - 1), "wall")
			_set_tile(Vector2i(start_col + k, row + 1), "wall")
	else:
		var north: Vector2i = a if a.y < b.y else b
		var origin := _slot_origin(north)
		var col := origin.x + mid_col
		var start_row := origin.y + ROOM_H
		for k in CORRIDOR:
			_set_tile(Vector2i(col, start_row + k), "floor")
			_set_tile(Vector2i(col - 1, start_row + k), "wall")
			_set_tile(Vector2i(col + 1, start_row + k), "wall")


# ---------------------------------------------------------------- tiles ----

func _set_tile(pos: Vector2i, kind: String) -> void:
	if kind == "floor":
		_tiles[pos] = "floor"
	elif _tiles.get(pos, "") != "floor":
		_tiles[pos] = "wall"


func _render_tiles() -> void:
	var floor_texture := ContentLibrary.get_tile(_floor_tile, Vector2i(tile, tile))
	var wall_texture := ContentLibrary.get_tile(_wall_tile, Vector2i(tile, tile))
	for pos: Vector2i in _tiles:
		var world := Vector2(pos.x * tile + tile * 0.5, pos.y * tile + tile * 0.5)
		var sprite := Sprite2D.new()
		if _tiles[pos] == "wall":
			sprite.texture = wall_texture
			_wall_sprites.add_child(sprite)
			sprite.global_position = world
			var collision := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(tile, tile)
			collision.shape = rect
			collision.position = world
			_walls.add_child(collision)
		else:
			sprite.texture = floor_texture
			_floors.add_child(sprite)
			sprite.global_position = world


func _make_container(container_name: String, z: int) -> Node2D:
	var node := Node2D.new()
	node.name = container_name
	node.z_index = z
	add_child(node)
	return node


func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = array[i]
		array[i] = array[j]
		array[j] = tmp
