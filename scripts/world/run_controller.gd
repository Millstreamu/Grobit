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
var lighting: LightingSystem
var hud: Hud
var _run_over := false
var start_position := Vector2.ZERO
var _lair: Room           # the start room, used as the goblin's home base
var _lair_exit: Door      # the lair's doorway the scrapbot drives out through


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

	# Persistent factory: carry over the layout you built last run (machines, transport,
	# modules). begin_run() made a bare grid; replace it with the saved one if there is one.
	var fresh_factory := not MetaState.has_factory()
	if not fresh_factory:
		var saved := MetaState.load_factory()
		if saved != null:
			RunState.factory = saved
	_ensure_scrapper_arm()  # every factory needs the Scrapper Arm (also migrates older saves)
	if fresh_factory:
		_seed_starter_factory()  # first run ever: a Copper Recycler next to the arm

	generator = AreaGenerator.new()
	generator.name = "Area"
	add_child(generator)
	# Deferred generation: build ONLY the lair now. The facility beyond its sealed door doesn't
	# exist until the player commits to a run by hopping in the scrapbot (see _drive_out), which
	# leaves room for run-choice options before the map is rolled.
	start_position = generator.build_lair(area_id)

	# Real-time driver for the inventory-factory (ticks even while the panel pauses
	# the tree, so processing stays live).
	var factory_processor := FactoryProcessor.new()
	factory_processor.name = "FactoryProcessor"
	add_child(factory_processor)

	build_manager = BuildManager.new()
	build_manager.name = "BuildManager"
	add_child(build_manager)

	# Darkness + vision (see LightingSystem). Created before the player so the cone
	# can be attached as soon as Grobit exists.
	lighting = LightingSystem.new()
	lighting.name = "Lighting"
	add_child(lighting)

	player = PLAYER_SCENE.instantiate() as GrobitPlayer
	player.global_position = start_position
	add_child(player)
	player.died.connect(_on_player_died)
	lighting.attach_player(player)
	# The start room is a lit safe room.
	lighting.add_lamp(start_position, 150.0)

	# The start room IS the lair (safe, empty, lit). Park the scrapbot at its exit so you
	# walk over as the goblin and [F] to hop in & drive out into the dark run. The run map is
	# already generated but unexplored (dark), so it reveals as you drive — seamless, no load.
	_lair = generator.rooms[0] if not generator.rooms.is_empty() else null
	var scrapbot_pos := start_position
	if _lair != null and not _lair.doors.is_empty():
		_lair_exit = _lair.doors[0]
		scrapbot_pos = _lair.nearest_interior_tile(_lair_exit.global_position)
	var scrapbot := Scrapbot.new()
	add_child(scrapbot)
	scrapbot.global_position = scrapbot_pos
	lighting.add_lamp(scrapbot_pos, 100.0, 1.0, Color(0.7, 1.0, 0.7))
	# (Component Exchange + System Terminal now spawn out in the map, not here.)

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
		RunState.factory.set_cell(Vector2i(2, 0), {"kind": "resource", "id": "copper"})
		RunState.factory.set_cell(Vector2i(3, 0), {"kind": "resource", "id": "charge_cells"})
		RunState.factory.set_cell(Vector2i(2, 1), {"kind": "resource", "id": "power_coupling"})
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
	var node_position: Variant = generator.claim_prop_tile(player.global_position + Vector2(32, 0))
	var station_position: Variant = generator.claim_prop_tile(player.global_position + Vector2(-32, 0))
	if node_position == null or station_position == null:
		push_warning("RunController: not enough safe start-room tiles for debug loot.")
		return
	var node := ScrapNode.new()
	node.generate({
		"label": "salvage", "tokens_min": 6, "tokens_max": 8,
		"rust_chance": 0.5, "rust_min": 1, "rust_max": 2, "loose_chance": 0.5,
		"pool": [{"id": "copper_scrap", "weight": 1}],
	})
	add_child(node)
	node.global_position = node_position
	var station := RepairStation.new()
	station.cost = {"copper": 2}
	station.reward = "ability"
	add_child(station)
	station.global_position = station_position


## Guarantees the factory has a Scrapper Arm (the harvest destination). Runs every launch so
## older saves without one get migrated; a no-op once an arm is present.
func _ensure_scrapper_arm() -> void:
	var f := RunState.factory
	if f == null:
		return
	for m: Dictionary in f.machines:
		if String(m.get("def_id", "")) == "scrapper_arm" and not bool(m.get("removed", false)):
			return
	var core := Vector2i(1, 1)  # a 5-cell bar: core + copper/steel/plastic/ceramic slots to the right
	if f.can_place("scrapper_arm", core):
		f.place_scrapper_arm(core)


## First-run bootstrap. You start at the bottom of the tech ladder: arm level 1 (steel only),
## with one Steel Recycler seeded, its input against the arm's steel slot — so harvested steel
## scrap flows straight in and the economy can start. Later tiers (copper → plastic → ceramic)
## unlock by leveling the arm. Only runs when there's no saved factory yet.
func _seed_starter_factory() -> void:
	var f := RunState.factory
	if f == null:
		return
	var core := Vector2i(3, 2)  # input at (2,2) sits directly below the steel slot at (2,1)
	if f.machine_at(core) < 0 and f.can_place("steel_recycler", core):
		f.place_machine("steel_recycler", core)


func _spawn_objective() -> void:
	if generator.objective_room == null:
		return
	var position: Variant = generator.claim_prop_tile(generator.objective_room.center(), generator.objective_room)
	if position == null:
		push_error("RunController: no safe objective-room tile for Objective Terminal.")
		return
	# Slice: a simple objective terminal that unlocks shipping when activated.
	var terminal := ObjectiveTerminal.new()
	add_child(terminal)
	terminal.global_position = position
	if lighting != null:
		lighting.add_lamp(terminal.global_position, 120.0, 1.1, Color(1.0, 0.8, 0.6))


## The scrapbot was used: in the lair it opens the factory loadout (set up, then Accept to
## launch); once out in the field it extracts and heads home.
func on_scrapbot_interact() -> void:
	if RunState.driving:
		_extract()  # already out — haul the whole inventory home, no picking
	elif hud != null:
		hud.open_factory()  # set up your loadout; [Enter] Accept drives you out (launch_from_setup)


## Called by the factory panel's Accept — the loadout is set, commit and drive out.
func launch_from_setup() -> void:
	_drive_out()


## Extraction is seamless now: whatever is in your factory inventory (loose resources + filled
## caches) comes home automatically — no load-the-cartridge selection screen.
func _extract() -> void:
	var items := {}
	var f := RunState.factory
	if f != null:
		for mi in f.machines.size():
			var cs := f.cache_state(mi)
			if not cs.is_empty() and int(cs.count) > 0:
				var cid := String(cs.id)
				items[cid] = int(items.get(cid, 0)) + f.take_cache(mi)
		for y in f.rows:
			for x in f.cols:
				var pos := Vector2i(x, y)
				var cell := f.get_cell(pos)
				if String(cell.get("kind", "")) == "resource":
					var id := String(cell.id)
					items[id] = int(items.get(id, 0)) + int(cell.get("count", 1))
					f.set_cell(pos, {})
	on_cartridge_shipped(items)


## Hop in the scrapbot and drive one tile out of the lair into the (dark) ruins. The facility
## is generated at THIS moment (not at run start) so a run-choice can shape it first.
func _drive_out() -> void:
	RunState.driving = true
	# PLACEHOLDER: a run-powerup/ability choice will go here (chosen as you commit to the run),
	# replacing the old game-start ability chooser. Left as a no-op until that slice.
	if generator != null and not generator.facility_ready():
		generator.generate_facility(run_seed)
	if _lair_exit != null:
		_lair_exit.unlock()  # open the way out
		if player != null:
			var dir := _lair_exit.global_position - start_position
			dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
			player.global_position = _lair_exit.global_position + dir * 36.0  # one tile into the run
	if hud != null:
		hud.log_message("You hop in the scrapbot and drive out into the ruins…")


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
	# The factory layout you built persists to the next run (extraction or death alike).
	# (A future big-machine extraction will clear it instead.)
	MetaState.save_factory(RunState.factory)
	if player != null:
		player.set_input_locked(true)
	var summary := RunState.end_run(result)
	hud.show_summary(result, summary)
	get_tree().paused = true


func restart_run() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


## DEBUG (F9): wipe the persistent factory + storage back to a single bare Scrapper Arm, then
## reload. Useful for testing the loop from a clean slate.
func debug_reset_to_arm() -> void:
	var g := FactoryGrid.new(RunState.FACTORY_COLS, RunState.FACTORY_ROWS)
	g.place_scrapper_arm(Vector2i(1, 1))
	MetaState.save_factory(g)            # persist a factory that holds only the arm
	MetaState.machine_storage.clear()    # empty the lair storage (transport/caches)
	MetaState.machine_instances.clear()  # and the stored machine instances
	MetaState.save_game()
	if hud != null:
		hud.log_message("DEBUG: factory + storage reset to a bare Scrapper Arm.")
	restart_run()
