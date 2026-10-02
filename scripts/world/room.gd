class_name Room
extends Node2D
## One generated room. Combat rooms lock their doors when Grobit enters, spawn
## enemies, and unlock once the objective (kill all enemies) is met. The
## completion check is factored out so other objective types can be added later.

signal room_cleared(room: Room)
signal room_activated(room: Room)

enum RoomType { START, COMBAT, OBJECTIVE, SALVAGE, HAZARD, SPAWNER, WORKSHOP }

const ENEMY_SCENE := preload("res://scenes/enemies/basic_enemy.tscn")
const PICKUP_SCENE := preload("res://scenes/resources/scrap_pickup.tscn")

var room_type := RoomType.COMBAT
# Irregular shape: the grid cells this room owns, the walkable floor-tile centres
# (world space) used for spawns, the cell size in pixels, and a cell-space centroid
# for the minimap.
var cells: Array[Vector2i] = []
var interior_tiles: Array[Vector2] = []
var cell_pixels := 0.0
var tile_size := 32.0
var map_position := Vector2.ZERO
var doors: Array[Door] = []
var enemy_min := 2
var enemy_max := 4
var enemy_id := "basic_enemy"
var enemy_weights: Dictionary = {}
var salvage_loot: Array = []
var hazard_config: Dictionary = {}
var spawners: Array[Spawner] = []
var spawner_config: Dictionary = {}
var rng := RandomNumberGenerator.new()

var is_cleared := false
var wave := 0            # spawner rooms: how many waves cleared so far
var _armed := true       # spawner rooms: ready to spawn a fresh wave on entry
var _active := false
var _alive := 0
var _trigger: Area2D
var _pending_players: Array[Node2D] = []

# Grobit's collision radius is 11 px. Requiring its centre to reach this inset
# leaves the whole body beyond the approach/door tiles before a door can lock.
const ACTIVATION_INSET := 12.0


# Exploration-first: rooms no longer seal the player in to clear a wave. Combat is
# now sparse ambient threats, so nothing locks doors on entry. (The lock/activate/
# wave code below is kept, unused, for a future objective-gate if we want one.)
func _locks_on_entry() -> bool:
	return false


func build_trigger() -> void:
	_trigger = Area2D.new()
	_trigger.collision_mask = 1
	_trigger.monitoring = true
	# One rectangle per owned cell covers the room's irregular footprint.
	for c: Vector2i in cells:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(cell_pixels, cell_pixels)
		shape.shape = rect
		shape.position = Vector2(c.x * cell_pixels + cell_pixels * 0.5, c.y * cell_pixels + cell_pixels * 0.5)
		_trigger.add_child(shape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)
	_trigger.body_exited.connect(_on_body_exited)


func center() -> Vector2:
	if interior_tiles.is_empty():
		return map_position * cell_pixels
	var sum := Vector2.ZERO
	for t: Vector2 in interior_tiles:
		sum += t
	return sum / interior_tiles.size()


## The interior floor-tile CENTER nearest `world_pos` — use this to place stations so they
## sit snapped on the grid rather than at an arbitrary pixel offset. `exclude` skips tiles
## already taken (so several stations land on distinct tiles).
func nearest_interior_tile(world_pos: Vector2, exclude: Array = []) -> Vector2:
	if interior_tiles.is_empty():
		return world_pos
	var best := world_pos
	var best_dist := INF
	var found := false
	for t: Vector2 in interior_tiles:
		if exclude.has(t):
			continue
		var d := t.distance_squared_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = t
			found = true
	return best if found else interior_tiles[0]


func _physics_process(_delta: float) -> void:
	for body: Node2D in _pending_players.duplicate():
		if not is_instance_valid(body):
			_pending_players.erase(body)
			continue
		if _is_fully_inside(body.global_position):
			_pending_players.erase(body)
			_enter_room()


## True only in the safe centre of a proper interior floor tile. Door and
## approach tiles are deliberately absent from interior_tiles, so a player's
## complete collision body must clear the passage before this becomes true.
func _is_fully_inside(world_position: Vector2) -> bool:
	var half_extent := maxf(0.0, tile_size * 0.5 - ACTIVATION_INSET)
	for tile_center: Vector2 in interior_tiles:
		var offset := world_position - tile_center
		if absf(offset.x) <= half_extent and absf(offset.y) <= half_extent:
			return true
	return false


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if body is Node2D and not _pending_players.has(body):
		_pending_players.append(body)


func _enter_room() -> void:
	# No sealing/waves. Combat & spawner rooms scatter a few ambient enemies the FIRST
	# time you enter (sparse, avoidable); everything else is exploration/production.
	if _active or is_cleared:
		return
	if room_type == RoomType.COMBAT or room_type == RoomType.SPAWNER:
		_active = true
		var count := rng.randi_range(enemy_min, enemy_max)
		for i in count:
			_spawn_enemy(_random_interior_point(), _pick_enemy())


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_pending_players.erase(body)


## Spawns the salvage room's guaranteed loot. Called once after the room is built.
func spawn_salvage() -> void:
	for drop: Dictionary in salvage_loot:
		if rng.randf() > float(drop.get("chance", 1.0)):
			continue
		var amount := rng.randi_range(int(drop.get("min", 1)), int(drop.get("max", 1)))
		if amount <= 0:
			continue
		var pickup := PICKUP_SCENE.instantiate()
		pickup.resource_id = String(drop.get("resource", "scrap_metal"))
		pickup.amount = amount
		pickup.global_position = _random_interior_point()
		add_child(pickup)


## Scatters harvestable scrap nodes — most rooms have some (the main resource income).
func spawn_harvest(config: Dictionary) -> void:
	if config.is_empty():
		return
	# New shape: config.nodes is a list of node kinds (scrap, e-waste, ...). Older
	# single-stream configs (yield/charges/per_room_* at the top level) still work.
	var node_defs: Array = config.get("nodes", [])
	if node_defs.is_empty():
		node_defs = [config]
	for def_variant: Variant in node_defs:
		var def: Dictionary = def_variant
		var count := rng.randi_range(int(def.get("per_room_min", 1)), int(def.get("per_room_max", 3)))
		for i in count:
			var node := ScrapNode.new()
			node.generate(def, rng)
			add_child(node)
			node.global_position = _random_interior_point()


## Places a persistent damage zone in the middle of a hazard room.
func spawn_hazard() -> void:
	if hazard_config.is_empty():
		return
	var hazard := HazardZone.new()
	hazard.damage = int(hazard_config.get("damage", 1))
	hazard.interval = float(hazard_config.get("interval", 0.6))
	hazard.radius = float(hazard_config.get("radius", 40.0))
	hazard.global_position = center()
	add_child(hazard)


# Combat / hazard / objective: a single locked wave that clears permanently.
func activate() -> void:
	_active = true
	_lock_doors()
	var count := rng.randi_range(enemy_min, enemy_max)
	for i in count:
		_spawn_enemy(_random_interior_point(), _pick_enemy())
	room_activated.emit(self)
	if _alive <= 0:
		_finish()


# Spawner rooms: a locked wave that re-arms on re-entry, growing each time.
func _start_wave() -> void:
	_active = true
	_armed = false
	_lock_doors()
	var base_count := int(spawner_config.get("base_count", 3))
	var growth := int(spawner_config.get("count_growth", 2))
	var count := base_count + wave * growth
	# Difficulty scaling is deliberately light for now (tune later): each wave adds
	# a flat health bonus and a small speed multiplier on top of each enemy's stats.
	var bonus_health := wave * int(spawner_config.get("health_per_wave", 0))
	var speed_mult := 1.0 + wave * float(spawner_config.get("speed_per_wave", 0.0))
	for i in count:
		var pos := _random_interior_point()
		if not spawners.is_empty():
			pos = spawners[i % spawners.size()].spawn_position()
		_spawn_enemy(pos, _pick_enemy(), bonus_health, speed_mult)
	wave += 1
	room_activated.emit(self)
	if _alive <= 0:
		_finish()


func _pick_enemy() -> String:
	if enemy_weights.is_empty():
		return enemy_id
	var total := 0
	for key: String in enemy_weights:
		total += int(enemy_weights[key])
	if total <= 0:
		return enemy_id
	var roll := rng.randi_range(1, total)
	var acc := 0
	for key: String in enemy_weights:
		acc += int(enemy_weights[key])
		if roll <= acc:
			return key
	return enemy_id


func _spawn_enemy(pos: Vector2, eid: String, bonus_health := 0, speed_mult := 1.0) -> void:
	var enemy := ENEMY_SCENE.instantiate() as BasicEnemy
	enemy.enemy_id = eid
	enemy.bonus_health = bonus_health
	enemy.speed_mult = speed_mult
	enemy.global_position = pos
	add_child(enemy)
	_alive += 1
	enemy.tree_exited.connect(_on_enemy_gone)


func _random_interior_point() -> Vector2:
	if interior_tiles.is_empty():
		return center()
	return interior_tiles[rng.randi_range(0, interior_tiles.size() - 1)]


func _on_enemy_gone() -> void:
	# Ignore teardown (e.g. scene reload) freeing enemies while the room exits.
	if not is_inside_tree():
		return
	_alive -= 1
	if _active and _alive <= 0:
		_finish()


func _lock_doors() -> void:
	for door: Door in doors:
		door.lock()


# Wave cleared: unlock. Spawner rooms stay re-armable; others clear permanently.
func _finish() -> void:
	_active = false
	for door: Door in doors:
		door.unlock()
	if room_type == RoomType.SPAWNER:
		return  # _armed is set when the player leaves
	is_cleared = true
	room_cleared.emit(self)
