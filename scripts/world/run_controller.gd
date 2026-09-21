class_name RunController
extends Node2D
## Top-level orchestrator for a single run. Generates the area, spawns Grobit and
## the run systems, and owns the run lifecycle: death/respawn, extraction, and
## repairing the Power Generator. Keeps RUN concerns here and defers PERMANENT
## progression to MetaState.

const PLAYER_SCENE := preload("res://scenes/player/grobit.tscn")

## -1 picks a fresh random seed each run; set a value to reproduce a layout.
@export var fixed_seed := -1

var area_id := ""
var run_seed := 0
var player: GrobitPlayer
var generator: AreaGenerator
var build_manager: BuildManager
var hud: Hud
var _run_over := false


func _ready() -> void:
	add_to_group("run_controller")
	# Pausable so a modal panel's get_tree().paused actually freezes the world
	# (player, enemies, build mode). Nodes that must keep running while paused set
	# their own PROCESS_MODE_ALWAYS: the HUD, the factory processor, and the modal
	# panels. (Restart from the end-of-run summary is driven by the always-on HUD.)
	process_mode = Node.PROCESS_MODE_PAUSABLE

	area_id = GameData.first_area_id()
	if area_id.is_empty():
		push_error("RunController: no areas defined in data.")
		return
	run_seed = fixed_seed if fixed_seed >= 0 else randi()
	RunState.begin_run(area_id, run_seed)

	generator = AreaGenerator.new()
	generator.name = "Area"
	add_child(generator)
	var start_position := generator.build(area_id, run_seed)

	# Real-time driver for the inventory-factory (ticks even while the panel pauses
	# the tree, so processing stays live).
	var factory_processor := FactoryProcessor.new()
	factory_processor.name = "FactoryProcessor"
	add_child(factory_processor)

	build_manager = BuildManager.new()
	build_manager.name = "BuildManager"
	add_child(build_manager)

	_spawn_objective()

	player = PLAYER_SCENE.instantiate() as GrobitPlayer
	player.global_position = start_position
	add_child(player)
	player.died.connect(_on_player_died)

	# Retrieval pad in the (safe) start room — where you ship out once the objective
	# is done. Slice: pre-placed; later a buildable in any cleared room.
	var pad := RetrievalPad.new()
	add_child(pad)
	pad.global_position = start_position + Vector2(0, 44)

	# Decode station in the start room so drafting modules is reachable (slice; later
	# these live in workshop rooms).
	var decode := DecodeStation.new()
	add_child(decode)
	decode.global_position = start_position + Vector2(-44, 44)

	var selection := SelectionManager.new()
	selection.name = "SelectionManager"
	add_child(selection)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player, build_manager, generator)
	build_manager.message.connect(hud.log_message)

	if OS.has_environment("GROBIT_DEBUG_ENEMIES"):
		_debug_spawn_enemies()
	if OS.has_environment("GROBIT_DEBUG_LOOT"):
		_debug_spawn_loot()
	# Env-gated: unlock shipping + seed factory items + open the cartridge loader.
	if OS.has_environment("GROBIT_OPEN_SHIP") and RunState.factory != null:
		RunState.unlock_shipping()
		RunState.factory.set_cell(Vector2i(2, 0), {"kind": "resource", "id": "metal_bar"})
		RunState.factory.set_cell(Vector2i(3, 0), {"kind": "resource", "id": "scrap_metal"})
		RunState.factory.set_cell(Vector2i(2, 1), {"kind": "resource", "id": "copper_wire"})
		hud.open_cartridge.call_deferred()

	# Report which artwork is still using placeholders (all icons now requested).
	ContentLibrary.print_missing_report.call_deferred()


# Debug helper (env-gated): spawns one of each enemy type near the start so their
# behaviour (including ranged fire) can be exercised without walking into a room.
func _debug_spawn_enemies() -> void:
	var i := 0
	for eid: String in GameData.enemies:
		var e := load("res://scenes/enemies/basic_enemy.tscn").instantiate() as BasicEnemy
		e.enemy_id = eid
		e.global_position = player.global_position + Vector2(60 + i * 34, 30)
		add_child(e)
		i += 1


# Debug helper (env-gated): a scrap node + repair station beside the start.
func _debug_spawn_loot() -> void:
	var node := ScrapNode.new()
	node.generate({
		"label": "salvage", "tokens_min": 6, "tokens_max": 8,
		"rust_chance": 0.5, "rust_min": 1, "rust_max": 2, "loose_chance": 0.5,
		"pool": [
			{"id": "bent_panel", "weight": 5},
			{"id": "cable_bundle", "weight": 3},
			{"id": "broken_motor", "weight": 2},
			{"id": "burnt_board", "weight": 2},
		],
	})
	add_child(node)
	node.global_position = player.global_position + Vector2(44, 0)
	var station := RepairStation.new()
	station.cost = {"scrap_metal": 2}
	station.reward = "ability"
	add_child(station)
	station.global_position = player.global_position + Vector2(-44, 0)

	# Env-gated: open the scrapping minigame on the spawned node for inspection.
	if OS.has_environment("GROBIT_OPEN_SCRAP") and hud != null:
		hud.open_scrap_minigame.call_deferred(node)


func _spawn_objective() -> void:
	if generator.objective_room == null:
		return
	# Slice: a simple objective terminal that unlocks shipping when activated.
	var terminal := ObjectiveTerminal.new()
	add_child(terminal)
	terminal.global_position = generator.objective_room.center()


## Ends the run, banking the loaded cartridge toward the permanent Mars total.
func on_cartridge_shipped(items: Dictionary) -> void:
	RunState.last_run_unlocks = MetaState.bank_delivery(items)
	_end_run(RunState.RESULT_SHIPPED)


func _on_player_died() -> void:
	if _run_over:
		return
	var beacon := _nearest_usable_beacon()
	if beacon != null and beacon.consume():
		player.respawn_at(beacon.global_position)
		hud.log_message("Respawned at beacon (%d use(s) left)." % beacon.uses)
		return
	_end_run(RunState.RESULT_LOST)


func _nearest_usable_beacon() -> RespawnBeacon:
	var best: RespawnBeacon
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group("respawn_beacons"):
		var beacon := node as RespawnBeacon
		if beacon == null or not beacon.has_use():
			continue
		var distance := player.global_position.distance_to(beacon.global_position)
		if distance < best_distance:
			best_distance = distance
			best = beacon
	return best


func _end_run(result: String) -> void:
	if _run_over:
		return
	_run_over = true
	if player != null:
		player.set_input_locked(true)
	var summary := RunState.end_run(result)
	hud.show_summary(result, summary)
	get_tree().paused = true


func restart_run() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
