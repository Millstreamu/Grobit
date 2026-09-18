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
var recycler_system: RecyclerSystem
var manufacturing: Manufacturing
var build_manager: BuildManager
var hud: Hud
var _run_over := false


func _ready() -> void:
	add_to_group("run_controller")
	process_mode = Node.PROCESS_MODE_ALWAYS

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

	recycler_system = RecyclerSystem.new()
	recycler_system.name = "RecyclerSystem"
	add_child(recycler_system)

	manufacturing = Manufacturing.new()
	manufacturing.name = "Manufacturing"
	add_child(manufacturing)

	build_manager = BuildManager.new()
	build_manager.name = "BuildManager"
	add_child(build_manager)

	_spawn_objective()

	player = PLAYER_SCENE.instantiate() as GrobitPlayer
	player.global_position = start_position
	add_child(player)
	player.died.connect(_on_player_died)

	var selection := SelectionManager.new()
	selection.name = "SelectionManager"
	add_child(selection)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player, recycler_system, manufacturing, build_manager, generator)
	build_manager.message.connect(hud.log_message)

	if OS.has_environment("GROBIT_DEBUG_ENEMIES"):
		_debug_spawn_enemies()
	if OS.has_environment("GROBIT_DEBUG_LOOT"):
		_debug_spawn_loot()

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
	node.yield_table = [{"resource": "raw_scrap", "min": 1, "max": 2, "chance": 1.0}]
	node.charges = 3
	add_child(node)
	node.global_position = player.global_position + Vector2(44, 0)
	var station := RepairStation.new()
	station.cost = {"metal": 2}
	station.reward = "ability"
	add_child(station)
	station.global_position = player.global_position + Vector2(-44, 0)
	var fab := Fabricator.new()
	add_child(fab)
	fab.global_position = player.global_position + Vector2(0, -48)


func _spawn_objective() -> void:
	if generator.objective_room == null:
		return
	var objective: Dictionary = GameData.area(area_id).get("objective", {})
	if String(objective.get("type", "")) != "power_generator":
		return
	var machine := PowerGenerator.new()
	machine.requires = (objective.get("requires", {}) as Dictionary).duplicate()
	machine.global_position = generator.objective_room.center()
	add_child(machine)
	machine.repaired.connect(_on_generator_repaired)


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


func on_extraction_confirmed() -> void:
	_end_run(RunState.RESULT_EXTRACTED)


func _on_generator_repaired() -> void:
	_end_run(RunState.RESULT_REPAIRED)


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
