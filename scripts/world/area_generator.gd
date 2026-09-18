class_name AreaGenerator
extends Node2D
## Seeded generator ported from the Config Studio tool (tools/config-studio).
## No corridors: rooms are irregular unions of grid CELLS (complex shapes) grown
## to fill a W×H cell grid, packed together. Adjacent rooms share a 2-tile wall
## with carved DOORWAYS at connections (spanning tree + loop_chance extra loops).
## Each passage has one grid-aligned door tile and one open approach tile; doors
## are never positioned on the half-tile boundary between rooms.
## Map-shape params come from data/game/generation.json (GameData.generation);
## gameplay params (enemy counts, room-type mix, harvest/repair/etc.) from area.json.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var tile := 32
var rooms: Array[Room] = []
var room_edges: Array = []  # [Vector2, Vector2] centroid pairs (cell space), for the minimap
var start_position := Vector2.ZERO
var objective_room: Room

# Shape state, shared with the tile helpers during build().
var _W := 6
var _H := 5
var _C := 5
var _TW := 0
var _TH := 0
var _cell: Array = []          # room index per grid cell
var _door_floors: Dictionary = {}  # both wall tiles carved for each passage
var _doorways: Array = []           # [room a, room b, tile a, tile b] per shared door

var _floors: Node2D
var _wall_sprites: Node2D
var _walls: StaticBody2D
var _doors_root: Node2D
var _floor_tile := "floor_clean"
var _wall_tile := "wall"

var _harvest_config: Dictionary = {}
var _repair_config: Dictionary = {}
var _spawner_config: Dictionary = {}
var _salvage_loot: Array = []
var _hazard_config: Dictionary = {}


func build(area_id: String, run_seed: int) -> Vector2:
	var area: Dictionary = GameData.area(area_id)
	_floor_tile = String(area.get("floor_tile", "floor_clean"))
	_wall_tile = String(area.get("wall_tile", "wall"))
	if ContentLibrary.tileset.tile_width > 0:
		tile = ContentLibrary.tileset.tile_width

	var shape: Dictionary = GameData.generation
	_W = maxi(2, int(shape.get("grid_width", 6)))
	_H = maxi(2, int(shape.get("grid_height", 5)))
	_C = maxi(3, int(shape.get("cell_size", 5)))
	_TW = _W * _C
	_TH = _H * _C
	var room_count := clampi(int(shape.get("room_count", 8)), 1, _W * _H)
	var rmin := int(shape.get("room_min_cells", 2))
	var rmax := int(shape.get("room_max_cells", 5))
	var door_width := maxi(1, int(shape.get("door_width", 2)))
	var loop_chance := float(shape.get("loop_chance", 0.15))

	# Gameplay params: prefer the tool-authored generation.json, fall back to area.json.
	var generation: Dictionary = area.get("generation", {})
	var enemy_min := int(shape.get("min_enemies", generation.get("min_enemies", 2)))
	var enemy_max := int(shape.get("max_enemies", generation.get("max_enemies", 4)))
	var weights: Dictionary = shape.get("room_type_weights", generation.get("room_type_weights", {"combat": 1}))
	var enemy_weights: Dictionary = shape.get("enemy_weights", area.get("enemy_weights", {}))
	var enemy_id := "basic_enemy"
	if area.get("enemies", []) is Array and not area.enemies.is_empty():
		enemy_id = String(area.enemies[0])
	# Gameplay content: prefer generation.json (tool-authored), fall back to area.json.
	_harvest_config = shape.get("harvest", area.get("harvest", {}))
	_repair_config = shape.get("repair", area.get("repair", {}))
	_spawner_config = shape.get("spawner", area.get("spawner", {}))
	_salvage_loot = shape.get("salvage_loot", area.get("salvage_loot", []))
	_hazard_config = shape.get("hazard", area.get("hazard", {}))

	_floors = _make_container("Floors", -2)
	_wall_sprites = _make_container("WallSprites", -1)
	_walls = StaticBody2D.new()
	_walls.name = "Walls"
	add_child(_walls)
	_doors_root = _make_container("Doors", -1)

	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed

	room_count = _grow_regions(rng, room_count, rmin, rmax)
	var neighbours := _room_adjacency(room_count)
	var connections := _connect_rooms(rng, room_count, neighbours, loop_chance)
	_carve_doors(rng, connections, door_width)

	# Room type assignment: start = room 0, objective = farthest by graph distance.
	var objective_index := _farthest_room(room_count, neighbours, 0)
	var types := _assign_types(rng, room_count, 0, objective_index, weights)

	_build_rooms(run_seed, room_count, types, enemy_min, enemy_max, enemy_id, enemy_weights)
	_render_tiles()
	for room: Room in rooms:
		room.build_trigger()
		_populate_room(room, enemy_id)

	_build_minimap_edges(connections)
	return start_position


# ----------------------------------------------------------- regions ----

func _grow_regions(rng: RandomNumberGenerator, room_count: int, rmin: int, rmax: int) -> int:
	var n := _W * _H
	_cell = []
	_cell.resize(n)
	_cell.fill(-1)

	var order := range(n)
	_shuffle(order, rng)
	var seeds := order.slice(0, room_count)
	var targets: Array = []
	var counts: Array = []
	for i in room_count:
		targets.append(rng.randi_range(rmin, maxi(rmin, rmax)))
		counts.append(1)
		_cell[seeds[i]] = i

	var grew := true
	var guard := 0
	while grew and guard < n * 6:
		guard += 1
		grew = false
		var room_order := range(room_count)
		_shuffle(room_order, rng)
		for r: int in room_order:
			if counts[r] >= targets[r]:
				continue
			var candidates: Array = []
			for c in n:
				if _cell[c] != r:
					continue
				var x := c % _W
				var y := c / _W
				for d: Vector2i in DIRS:
					var nx := x + d.x
					var ny := y + d.y
					if _in_grid(nx, ny) and _cell[ny * _W + nx] == -1:
						candidates.append(ny * _W + nx)
			if not candidates.is_empty():
				_cell[candidates[rng.randi_range(0, candidates.size() - 1)]] = r
				counts[r] += 1
				grew = true

	# Fill leftover unclaimed cells so the grid is fully packed (no gaps/corridors).
	var left := true
	var guard2 := 0
	while left and guard2 < n * 6:
		guard2 += 1
		left = false
		for c in n:
			if _cell[c] != -1:
				continue
			var x := c % _W
			var y := c / _W
			var near: Array = []
			for d: Vector2i in DIRS:
				var nx := x + d.x
				var ny := y + d.y
				if _in_grid(nx, ny) and _cell[ny * _W + nx] >= 0:
					near.append(_cell[ny * _W + nx])
			if not near.is_empty():
				_cell[c] = near[rng.randi_range(0, near.size() - 1)]
			else:
				left = true
	return room_count


func _room_adjacency(room_count: int) -> Array:
	var neighbours: Array = []
	for i in room_count:
		neighbours.append({})
	for y in _H:
		for x in _W:
			var r: int = _cell[y * _W + x]
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx := x + d.x
				var ny := y + d.y
				if not _in_grid(nx, ny):
					continue
				var r2: int = _cell[ny * _W + nx]
				if r2 != r:
					neighbours[r][r2] = true
					neighbours[r2][r] = true
	return neighbours


func _connect_rooms(rng: RandomNumberGenerator, room_count: int, neighbours: Array, loop_chance: float) -> Array:
	var connected := {}
	var seen: Array = []
	seen.resize(room_count)
	seen.fill(false)
	var queue: Array = [0]
	seen[0] = true
	while not queue.is_empty():
		var r: int = queue.pop_front()
		var list: Array = neighbours[r].keys()
		_shuffle(list, rng)
		for nb: int in list:
			if not seen[nb]:
				seen[nb] = true
				connected[_edge_key(r, nb)] = [r, nb]
				queue.append(nb)
	# Extra loop doors.
	for a in room_count:
		for b: int in neighbours[a].keys():
			if a < b and not connected.has(_edge_key(a, b)) and rng.randf() < loop_chance:
				connected[_edge_key(a, b)] = [a, b]
	return connected.values()


func _farthest_room(room_count: int, neighbours: Array, from_room: int) -> int:
	var dist: Array = []
	dist.resize(room_count)
	dist.fill(-1)
	dist[from_room] = 0
	var queue: Array = [from_room]
	var farthest := from_room
	while not queue.is_empty():
		var r: int = queue.pop_front()
		for nb: int in neighbours[r].keys():
			if dist[nb] < 0:
				dist[nb] = dist[r] + 1
				if dist[nb] > dist[farthest]:
					farthest = nb
				queue.append(nb)
	return farthest


# --------------------------------------------------------------- doors ----

func _carve_doors(rng: RandomNumberGenerator, connections: Array, door_width: int) -> void:
	_door_floors.clear()
	_doorways.clear()
	for edge: Array in connections:
		var a: int = edge[0]
		var b: int = edge[1]
		var pairs: Array = []  # [ta:Vector2i, tb:Vector2i] border tile pairs (a beside b)
		for ty in _TH:
			for tx in _TW:
				if _room_of_tile(tx, ty) != a:
					continue
				for d: Vector2i in DIRS:
					var nx := tx + d.x
					var ny := ty + d.y
					if nx < 0 or ny < 0 or nx >= _TW or ny >= _TH:
						continue
					if _room_of_tile(nx, ny) == b:
						pairs.append([Vector2i(tx, ty), Vector2i(nx, ny)])
		if pairs.is_empty():
			continue
		var start: Array = pairs[rng.randi_range(0, pairs.size() - 1)]
		var horiz: bool = start[0].x != start[1].x  # passage runs vertically along the shared edge
		for k in door_width:
			for p: Array in pairs:
				var match_pair := false
				if horiz:
					match_pair = p[0].x == start[0].x and p[0].y == start[0].y + k
				else:
					match_pair = p[0].y == start[0].y and p[0].x == start[0].x + k
				if match_pair:
					# The adjoining rooms each contribute a wall tile to the passage,
					# but they share one Door positioned on the boundary between them.
					_door_floors[p[0]] = true
					_door_floors[p[1]] = true
					_doorways.append([a, b, p[0], p[1]])


# --------------------------------------------------------------- build ----

func _build_rooms(run_seed: int, room_count: int, types: Array, enemy_min: int, enemy_max: int, enemy_id: String, enemy_weights: Dictionary) -> void:
	# Create empty Room nodes with their owned cells; tiles/doors filled by _render_tiles.
	var cell_lists: Array = []
	var centroids: Array = []
	for i in room_count:
		cell_lists.append([])
		centroids.append(Vector2.ZERO)
	for y in _H:
		for x in _W:
			var r: int = _cell[y * _W + x]
			cell_lists[r].append(Vector2i(x, y))
			centroids[r] += Vector2(x, y)

	rooms.clear()
	for i in room_count:
		var room := Room.new()
		room.name = "Room_%d" % i
		room.room_type = types[i]
		room.cell_pixels = float(_C * tile)
		room.tile_size = float(tile)
		room.cells.assign(cell_lists[i])
		var count: int = maxi(1, cell_lists[i].size())
		room.map_position = centroids[i] / count
		room.enemy_id = enemy_id
		room.enemy_weights = enemy_weights
		room.salvage_loot = _salvage_loot
		room.hazard_config = _hazard_config
		if types[i] == Room.RoomType.START or types[i] == Room.RoomType.SALVAGE or types[i] == Room.RoomType.SPAWNER or types[i] == Room.RoomType.WORKSHOP:
			room.enemy_min = 0
			room.enemy_max = 0
		else:
			room.enemy_min = enemy_min
			room.enemy_max = enemy_max
		room.rng.seed = run_seed ^ ((i + 1) * 2654435761)
		add_child(room)
		rooms.append(room)
		if types[i] == Room.RoomType.OBJECTIVE:
			objective_room = room


func _render_tiles() -> void:
	var floor_texture := ContentLibrary.get_tile(_floor_tile, Vector2i(tile, tile))
	var wall_texture := ContentLibrary.get_tile(_wall_tile, Vector2i(tile, tile))
	for ty in _TH:
		for tx in _TW:
			var r: int = _room_of_tile(tx, ty)
			var world := Vector2(tx * tile + tile * 0.5, ty * tile + tile * 0.5)
			var pos := Vector2i(tx, ty)
			if _door_floors.has(pos):
				_add_floor(floor_texture, world)
			elif _is_wall(tx, ty):
				_add_wall(wall_texture, world)
			else:
				_add_floor(floor_texture, world)
				rooms[r].interior_tiles.append(world)
	# A doorway belongs to both adjacent rooms. One of the two former wall tiles is
	# the grid-aligned door and the other is its open approach. Sharing that Door
	# ensures either room locks the one physical barrier instead of making two.
	for doorway: Array in _doorways:
		var door := Door.new()
		_doors_root.add_child(door)
		var tile_a: Vector2i = doorway[2]
		door.global_position = Vector2(tile_a) * tile + Vector2.ONE * tile * 0.5
		rooms[doorway[0]].doors.append(door)
		rooms[doorway[1]].doors.append(door)
	# Player starts in the middle of the start room.
	start_position = rooms[0].center()


func _add_floor(texture: Texture2D, world: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	_floors.add_child(sprite)
	sprite.global_position = world


func _add_wall(texture: Texture2D, world: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	_wall_sprites.add_child(sprite)
	sprite.global_position = world
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(tile, tile)
	collision.shape = rect
	collision.position = world
	_walls.add_child(collision)


func _build_minimap_edges(connections: Array) -> void:
	room_edges.clear()
	for edge: Array in connections:
		room_edges.append([rooms[edge[0]].map_position, rooms[edge[1]].map_position])


# ----------------------------------------------------- room population ----

func _populate_room(room: Room, enemy_id: String) -> void:
	if room.room_type != Room.RoomType.START:
		room.spawn_harvest(_harvest_config)
	match room.room_type:
		Room.RoomType.SALVAGE:
			room.spawn_salvage()
		Room.RoomType.HAZARD:
			room.spawn_hazard()
		Room.RoomType.SPAWNER:
			_add_spawners(room, _spawner_config, enemy_id)
		Room.RoomType.WORKSHOP:
			_add_repair_station(room)


func _add_repair_station(room: Room) -> void:
	var station := RepairStation.new()
	station.cost = (_repair_config.get("cost", {}) as Dictionary).duplicate()
	var rewards: Array = _repair_config.get("rewards", ["max_health"])
	if not rewards.is_empty():
		station.reward = String(rewards[room.rng.randi_range(0, rewards.size() - 1)])
	room.add_child(station)
	station.global_position = room.center()


func _add_spawners(room: Room, config: Dictionary, _enemy_id: String) -> void:
	room.spawner_config = config
	var markers := maxi(1, int(config.get("markers", 1)))
	for i in markers:
		var spawner := Spawner.new()
		room.add_child(spawner)
		spawner.global_position = room._random_interior_point()
		room.spawners.append(spawner)


func _assign_types(rng: RandomNumberGenerator, room_count: int, start_index: int, objective_index: int, weights: Dictionary) -> Array:
	var types: Array = []
	for i in room_count:
		if i == start_index:
			types.append(Room.RoomType.START)
		elif i == objective_index:
			types.append(Room.RoomType.OBJECTIVE)
		else:
			types.append(_pick_room_type(weights, rng))
	return types


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
		"workshop": return Room.RoomType.WORKSHOP
	return Room.RoomType.COMBAT


# ------------------------------------------------------------- helpers ----

func _room_of_tile(tx: int, ty: int) -> int:
	return _cell[(ty / _C) * _W + (tx / _C)]


func _is_wall(tx: int, ty: int) -> bool:
	var r := _room_of_tile(tx, ty)
	for d: Vector2i in DIRS:
		var nx := tx + d.x
		var ny := ty + d.y
		if nx < 0 or ny < 0 or nx >= _TW or ny >= _TH:
			return true
		if _room_of_tile(nx, ny) != r:
			return true
	return false


func _in_grid(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < _W and y < _H


func _edge_key(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]


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
