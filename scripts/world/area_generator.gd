class_name AreaGenerator
extends Node2D
## Seeded generator ported from the Config Studio tool (tools/config-studio).
## No corridors: rooms are irregular unions of grid CELLS (complex shapes) grown
## to fill a W×H cell grid, packed together. Adjacent rooms are separated by a
## single shared wall tile (on the lower-index room's side); a connection carves
## exactly ONE of those tiles into a grid-aligned door (spanning tree +
## loop_chance extra loops) — no corridors, no double walls.
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
var _door_floors: Dictionary = {}  # the single wall tile carved for each passage
var _doorways: Array = []           # [room a, room b, door tile] per shared door

var _floors: Node2D
var _wall_sprites: Node2D
var _walls: StaticBody2D
var _occluders: Node2D
var _wall_occluder: OccluderPolygon2D  # shared unit-square, reused by every wall
var _doors_root: Node2D
var _floor_tile := "floor_clean"
var _wall_tile := "wall"

var _harvest_config: Dictionary = {}
var _repair_config: Dictionary = {}
var _spawner_config: Dictionary = {}
var _salvage_loot: Array = []
var _machine_finds: Dictionary = {}
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
	_machine_finds = shape.get("machine_finds", area.get("machine_finds", {}))

	_floors = _make_container("Floors", -2)
	_wall_sprites = _make_container("WallSprites", -1)
	_walls = StaticBody2D.new()
	_walls.name = "Walls"
	add_child(_walls)
	# Light occlusion: walls block light and cast shadows (see LightingSystem). One
	# tile-sized square polygon, shared by every wall occluder — cheap to build.
	_occluders = _make_container("Occluders", 0)
	_wall_occluder = OccluderPolygon2D.new()
	var half := tile * 0.5
	_wall_occluder.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
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

	_spawn_guaranteed_chain(rng)
	_build_minimap_edges(connections)
	return start_position


## Guarantees at least one broken machine of EACH category (Recycler / Ammo Maker /
## Component Maker), each pre-decided to a concrete specialisation, and records the run
## chain on RunState for the debug panel. Specialisations are rolled independently, so
## the run may be incompatible with the weapon — intentional.
func _spawn_guaranteed_chain(rng: RandomNumberGenerator) -> void:
	var categories: Array = _machine_finds.get("categories", _default_find_categories())
	var non_start: Array = []
	for r: Room in rooms:
		if r.room_type != Room.RoomType.START and not r.interior_tiles.is_empty():
			non_start.append(r)
	if non_start.is_empty():
		return
	for cat: Dictionary in categories:
		if bool(cat.get("no_guarantee", false)):
			continue  # weapons are an optional find, not part of the guaranteed chain
		var pool: Array = cat.get("pool", [])
		if pool.is_empty():
			continue
		var pick: Variant = pool[rng.randi_range(0, pool.size() - 1)]
		var spec_id := String(pick.get("id", "")) if pick is Dictionary else String(pick)
		RunState.run_chain[String(cat.get("category", "Machine"))] = spec_id
		var room: Room = non_start[rng.randi_range(0, non_start.size() - 1)]
		var pickup := MachinePickup.new()
		pickup.broken = true
		pickup.category = String(cat.get("category", "Machine"))
		pickup.spec_pool = [spec_id]  # pre-decided: repair reveals exactly this
		pickup.repair_cost = cat.get("repair_cost", {})
		room.add_child(pickup)
		pickup.global_position = room._random_interior_point()


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
		var lo := mini(a, b)
		var hi := maxi(a, b)
		# The single shared wall lives on the lower room's boundary tiles adjacent
		# to the higher room. A tile only makes a usable door when the floor on
		# BOTH sides is open — so corner tiles (a wall on the approach) are skipped
		# and stay walls, and doors land mid-edge where they're actually reachable.
		var wall_dir := {}  # Vector2i tile -> direction toward the higher room
		var accessible: Array = []
		var fallback: Array = []
		for ty in _TH:
			for tx in _TW:
				if _room_of_tile(tx, ty) != lo:
					continue
				for d: Vector2i in DIRS:
					var nx := tx + d.x
					var ny := ty + d.y
					if nx < 0 or ny < 0 or nx >= _TW or ny >= _TH:
						continue
					if _room_of_tile(nx, ny) == hi:
						var t := Vector2i(tx, ty)
						wall_dir[t] = d
						fallback.append(t)
						var lo_app := t - d  # approach into the lower room
						if lo_app.x >= 0 and lo_app.y >= 0 and lo_app.x < _TW and lo_app.y < _TH \
								and not _is_wall(lo_app.x, lo_app.y) and not _is_wall(nx, ny):
							accessible.append(t)
						break
		var pool: Array = accessible if not accessible.is_empty() else fallback
		if pool.is_empty():
			continue
		var start: Vector2i = pool[rng.randi_range(0, pool.size() - 1)]
		var to_hi: Vector2i = wall_dir[start]
		var along := Vector2i(0, 1) if to_hi.x != 0 else Vector2i(1, 0)
		for k in door_width:
			var t: Vector2i = start + along * k
			if wall_dir.has(t):
				_door_floors[t] = true
				_doorways.append([a, b, t])


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
				_add_wall(wall_texture, world, tx, ty)
			else:
				_add_floor(floor_texture, world)
				rooms[r].interior_tiles.append(world)
	# One shared door tile per passage, owned by both adjacent rooms so either can
	# lock the single physical barrier.
	for doorway: Array in _doorways:
		var door := Door.new()
		_doors_root.add_child(door)
		var door_tile: Vector2i = doorway[2]
		door.global_position = Vector2(door_tile) * tile + Vector2.ONE * tile * 0.5
		rooms[doorway[0]].doors.append(door)
		rooms[doorway[1]].doors.append(door)
	# Player starts in the middle of the start room.
	start_position = rooms[0].center()


func _add_floor(texture: Texture2D, world: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	# Dim the open floor so walls read as the brighter structure in ambient light.
	sprite.self_modulate = LightingSystem.FLOOR_TINT
	_floors.add_child(sprite)
	sprite.global_position = world


func _add_wall(texture: Texture2D, world: Vector2, tx: int, ty: int) -> void:
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
	# Only walls with an open (non-wall) neighbour can ever be reached by light, so
	# skip occluders on fully-buried tiles to keep the shadow-caster count down.
	if _has_open_neighbour(tx, ty):
		var occluder := LightOccluder2D.new()
		occluder.occluder = _wall_occluder
		occluder.position = world
		_occluders.add_child(occluder)


func _has_open_neighbour(tx: int, ty: int) -> bool:
	for d: Vector2i in DIRS:
		var nx := tx + d.x
		var ny := ty + d.y
		if nx < 0 or ny < 0 or nx >= _TW or ny >= _TH:
			continue  # off-map counts as solid, never an opening
		if not _is_wall(nx, ny):
			return true
	return false


## Snaps a world position onto the nearest floor-tile center of `room` (default the start
## room) so pre-placed stations line up with the grid. `exclude` keeps several stations on
## distinct tiles.
func snap_to_tile(world_pos: Vector2, room: Room = null, exclude: Array = []) -> Vector2:
	var r := room
	if r == null and not rooms.is_empty():
		r = rooms[0]
	if r == null:
		return world_pos
	return r.nearest_interior_tile(world_pos, exclude)


## The room containing (or nearest to) a world position — the room that owns the
## floor tile closest to it. Used by the Power Relay to know which room to light.
func room_at(world_position: Vector2) -> Room:
	var best: Room = null
	var best_dist := INF
	for r: Room in rooms:
		for t: Vector2 in r.interior_tiles:
			var d := t.distance_squared_to(world_position)
			if d < best_dist:
				best_dist = d
				best = r
	return best


func _build_minimap_edges(connections: Array) -> void:
	room_edges.clear()
	for edge: Array in connections:
		room_edges.append([rooms[edge[0]].map_position, rooms[edge[1]].map_position])


# ----------------------------------------------------- room population ----

func _populate_room(room: Room, enemy_id: String) -> void:
	if room.room_type != Room.RoomType.START:
		room.spawn_harvest(_harvest_config)
		_maybe_spawn_machine(room)
		_maybe_spawn_fabricator(room)
	match room.room_type:
		Room.RoomType.SALVAGE:
			room.spawn_salvage()
		Room.RoomType.HAZARD:
			room.spawn_hazard()
		Room.RoomType.SPAWNER:
			_add_spawners(room, _spawner_config, enemy_id)
		Room.RoomType.WORKSHOP:
			_add_repair_station(room)


## Machines are FOUND BROKEN: each non-start room has a chance to hold one on a floor
## tile. Repairing it (in MachinePickup) rolls its specialisation. Config:
## machine_finds { chance, per_room_max, categories:[{category, repair_cost, pool}] };
## with no categories it defaults to a broken Recycler (the 4 material recyclers).
func _maybe_spawn_machine(room: Room) -> void:
	var chance := float(_machine_finds.get("chance", 0.45))
	var per_room := int(_machine_finds.get("per_room_max", 1))
	var categories: Array = _machine_finds.get("categories", _default_find_categories())
	if categories.is_empty():
		return
	for _i in per_room:
		if room.rng.randf() >= chance:
			continue
		var cat: Dictionary = _weighted_category(categories, room.rng)
		var pickup := MachinePickup.new()
		pickup.broken = true
		pickup.category = String(cat.get("category", "Machine"))
		# FIXED specialisation: pre-roll one id now so the pile knows (and reveals) exactly
		# what it becomes. This stops fishing for a family by repairing many random makers.
		pickup.spec_pool = [_pick_spec(cat.get("pool", []), room.rng)]
		pickup.repair_cost = cat.get("repair_cost", {})
		room.add_child(pickup)
		pickup.global_position = room._random_interior_point()


## Picks a category by its `weight` (default 1). Ammo Makers carry a low weight so they
## are the scarce find — you can't rely on your weapon's family turning up.
func _weighted_category(categories: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for c: Dictionary in categories:
		total += float(c.get("weight", 1))
	var pick := rng.randf() * total
	for c: Dictionary in categories:
		pick -= float(c.get("weight", 1))
		if pick <= 0.0:
			return c
	return categories[categories.size() - 1]


## Weighted pick of one spec id from a category pool.
func _pick_spec(pool: Array, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	var total := 0.0
	for e: Variant in pool:
		total += float(e.get("weight", 1)) if e is Dictionary else 1.0
	var pick := rng.randf() * total
	for e: Variant in pool:
		pick -= float(e.get("weight", 1)) if e is Dictionary else 1.0
		if pick <= 0.0:
			return String(e.get("id", "")) if e is Dictionary else String(e)
	var last: Variant = pool[pool.size() - 1]
	return String(last.get("id", "")) if last is Dictionary else String(last)


## The prototype default: broken Recyclers and Ammo Makers, each specialising randomly
## on repair. (Component Makers get added as another category next slice.)
func _default_find_categories() -> Array:
	return [
		{
			"category": "Recycler",
			"weight": 3,
			"repair_cost": {"junk": 2},
			"pool": [
				{"id": "copper_recycler", "weight": 1},
				{"id": "steel_recycler", "weight": 1},
				{"id": "plastic_recycler", "weight": 1},
				{"id": "ceramic_recycler", "weight": 1},
			],
		},
		{
			"category": "Ammo Maker",
			"weight": 1,
			"repair_cost": {"junk": 3},
			"pool": [
				{"id": "copper_ammo_maker", "weight": 1},
				{"id": "steel_ammo_maker", "weight": 1},
				{"id": "plastic_ammo_maker", "weight": 1},
				{"id": "ceramic_ammo_maker", "weight": 1},
			],
		},
		{
			"category": "Component Maker",
			"weight": 3,
			"repair_cost": {"junk": 4},
			"pool": [
				{"id": "coupling_maker", "weight": 1},
				{"id": "control_maker", "weight": 1},
				{"id": "frame_maker", "weight": 1},
				{"id": "thermal_maker", "weight": 1},
			],
		},
		{
			"category": "Weapon",
			"weight": 2,
			"no_guarantee": true,  # an optional upgrade over the basic gun, never guaranteed
			"repair_cost": {"junk": 3},
			"pool": [
				{"id": "copper_weapon", "weight": 1},
				{"id": "steel_weapon", "weight": 1},
				{"id": "plastic_weapon", "weight": 1},
				{"id": "ceramic_weapon", "weight": 1},
			],
		},
	]


## A Fabricator workbench turns up in a few rooms (see FabricatorStation).
func _maybe_spawn_fabricator(room: Room) -> void:
	if room.rng.randf() >= float(_machine_finds.get("fabricator_chance", 0.2)):
		return
	var station := FabricatorStation.new()
	room.add_child(station)
	station.global_position = room._random_interior_point()


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


const DIAGONALS := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


# Single shared wall between rooms: a boundary tile is only a wall on the
# lower-index room's side (or at the map edge). Adjacent rooms are separated by
# exactly ONE wall tile, so carving it makes a true one-tile door.
func _is_wall_base(tx: int, ty: int) -> bool:
	var r := _room_of_tile(tx, ty)
	for d: Vector2i in DIRS:
		var nx := tx + d.x
		var ny := ty + d.y
		if nx < 0 or ny < 0 or nx >= _TW or ny >= _TH:
			return true
		if _room_of_tile(nx, ny) > r:
			return true
	return false


func _is_wall(tx: int, ty: int) -> bool:
	if _is_wall_base(tx, ty):
		return true
	# Fill diagonal corner gaps so wall turns are proper 90° corners (no two walls
	# sitting only diagonally with floor between them). Only the lower-index room's
	# tile fills, and only when both tiles bridging to the diagonal are already
	# walls — so straight edges stay single-thickness.
	var r := _room_of_tile(tx, ty)
	for diag: Vector2i in DIAGONALS:
		var dxp := tx + diag.x
		var dyp := ty + diag.y
		if dxp < 0 or dyp < 0 or dxp >= _TW or dyp >= _TH:
			continue
		if _room_of_tile(dxp, dyp) <= r:
			continue
		if _is_wall_base(tx + diag.x, ty) and _is_wall_base(tx, ty + diag.y):
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
