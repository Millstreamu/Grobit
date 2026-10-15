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

	# Persistent INVENTORY grid: carry over last run's stored items. begin_run() made a bare grid;
	# replace it with the saved one if there is one. (The old recycler/maker factory is retired — this
	# grid is now pure storage; production is the process lines below.)
	if MetaState.has_factory():
		var saved := MetaState.load_factory()
		if saved != null:
			RunState.factory = saved
	# The module-bay loadout persists too — load the saved one over the empty bay.
	var saved_bay := MetaState.load_bay()
	if saved_bay != null:
		RunState.bay = saved_bay
	# The PROCESS LINES (production) persist the same way — carry over the layout you laid, or seed a
	# starter line on a brand-new game so run 1 can already make a product.
	var saved_line := MetaState.load_process()
	if saved_line != null:
		RunState.process_grid = saved_line
	elif not MetaState.has_process_line():
		_seed_starter_line()

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

	# The buildable LAIR STATIONS (Phase 1) replace the single System Terminal — recruiting, upgrading,
	# the production floor, the Mission Board etc. are each their own station, placed with build mode.
	_spawn_lair_stations(scrapbot_pos)

	var selection := SelectionManager.new()
	selection.name = "SelectionManager"
	add_child(selection)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player, build_manager, generator)
	build_manager.message.connect(hud.log_message)

	# Guided first run (Phase 6): a one-time nudge the moment you're stood in the lair.
	if not RunState.driving and hud.has_method("nudge"):
		hud.nudge("lair_intro", "This is your lair. [F] a station to use it, [B] to build/move stations. Board the scrapbot to head out.")

	# Harvest mode: park the bot in a room and [E] to pour the colony out to strip it (they haul
	# scrap back to the bot's arm), [E] again to recall. The siege/defenses come in later slices.
	var harvest := HarvestMode.new()
	harvest.name = "HarvestMode"
	harvest.bot = player
	harvest.hud = hud
	harvest.generator = generator
	add_child(harvest)

	if OS.has_environment("GROBIT_DEBUG_ENEMIES"):
		_debug_spawn_enemies()
	if OS.has_environment("GROBIT_DEBUG_LOOT"):
		_debug_spawn_loot()

	# Report which artwork is still using placeholders (all icons now requested).
	ContentLibrary.print_missing_report.call_deferred()


## Phase 1: rebuild the lair's STATIONS from the saved layout. On a brand-new lair, seeds the free
## defaults (Workshop + Mission Board) on distinct interior tiles and records them; thereafter every
## station the player has built is restored at its saved tile. Build mode ([B]) adds/moves/removes them.
func _spawn_lair_stations(exclude_pos: Vector2) -> void:
	if _lair == null:
		return
	var tsize: float = _lair.tile_size if _lair.tile_size > 0.0 else 32.0
	if not MetaState.has_lair_stations():
		# Fresh lair: the free defaults (Process Line + Mission Board). A Debug Lair places EVERY station.
		var to_place: Array = GameData.stations.keys() if MetaState.debug_pending else ["line", "missions"]
		var used: Array = [exclude_pos]
		for stype: String in to_place:
			var p: Variant = _lair.claim_nearest_prop_tile(start_position)
			if p == null:
				p = _lair.nearest_interior_tile(start_position, used)
			used.append(p)
			MetaState.add_lair_station(stype, int(floor(p.x / tsize)), int(floor(p.y / tsize)))
	if MetaState.debug_pending:
		_debug_stock_inventory()   # drop a materials/food/tech bundle so every system is testable now
		MetaState.debug_pending = false
		MetaState.save_game()
	for s: Dictionary in MetaState.lair_stations:
		var world := Vector2(int(s.get("x", 0)) * tsize + tsize * 0.5, int(s.get("y", 0)) * tsize + tsize * 0.5)
		var station := LairStation.new()
		station.station_type = String(s.get("type", ""))
		add_child(station)
		station.global_position = world
		lighting.add_lamp(world, 110.0, 1.0, Color(0.6, 0.85, 1.0))


## Debug Lair: stock the inventory so every station/system can be exercised immediately.
func _debug_stock_inventory() -> void:
	for m: String in ["steel", "copper", "plastic", "ceramic"]:
		RunState.add(m, 30)
	for s: String in ["steel_scrap", "copper_scrap", "plastic_scrap", "ceramic_scrap"]:
		RunState.add(s, 20)
	RunState.add("food", 40)
	RunState.add("tech_data", 25)


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


## First-run bootstrap. You start at the bottom of the tech ladder: every goblin carries the
## tier-1 (steel) tool, and a starter PROCESS LINE is seeded (steel_scrap → Heater → Presser = steel
## plate) so harvested steel scrap can be refined from the first run. Higher tiers come from better
## tools found in the field. Only runs on a brand-new game (no saved line yet).
func _seed_starter_line() -> void:
	var g := RunState.process_grid
	if g == null:
		return
	g.set_intake(Vector2i(0, 2), Vector2i(1, 0), "steel_scrap")   # steel scrap enters (1,2) going right
	g.place("heat", Vector2i(1, 2), Vector2i(-1, 0), Vector2i(1, 0))
	g.place("press", Vector2i(2, 2), Vector2i(-1, 0), Vector2i(1, 0))


## The scrapbot was used: in the lair it opens the SCRAPBOT window (bay / hold / crew squad, and
## [Enter] launches the run); once out in the field it extracts and heads home.
func on_scrapbot_interact() -> void:
	if RunState.driving:
		_extract()  # already out — haul the whole inventory home, no picking
	elif hud != null:
		hud.open_scrapbot()  # loadout + squad; [Enter] launches the run (launch_from_setup)


## Called by the Scrapbot window's [Enter] — the loadout + squad are set, commit and drive out.
func launch_from_setup() -> void:
	RunState.load_ammo()  # load the workshop-made ammo onto the bot for the weapon(s) in the bay
	_drive_out()


## Extraction is seamless now: whatever is in your factory inventory (loose resources + filled
## caches) comes home automatically — no load-the-cartridge selection screen.
## Base materials (scrap + the refined recycler outputs) stay in the PERSISTENT inventory — the
## colony hauls them home and spends them in the lair (tool upgrades, repairs). Only finished
## COMPONENTS (bridge parts + ship components) are delivered on extraction, toward the lair's
## survival needs + the Mars unlock tallies.
const _KEPT_IN_INVENTORY := ["steel_scrap", "copper_scrap", "plastic_scrap", "ceramic_scrap",
	"steel", "copper", "plastic", "ceramic", "tech_data", "food"]


func _extract() -> void:
	var items := {}
	var f := RunState.factory
	RunState.return_ammo()  # unspent ammo comes home to the workshop stock for next time
	# Drain the bot's CARGO HOLD into the persistent base inventory first: hauled scrap feeds the
	# grid, recovered machines go into per-instance storage (transport parts into fungible stock).
	if RunState.cargo != null and f != null:
		var hauled := RunState.cargo.scrap_counts()
		for sid: String in hauled:
			RunState.deposit(sid, int(hauled[sid]))
			RunState.run_stats["scrap_hauled"] = int(RunState.run_stats.get("scrap_hauled", 0)) + int(hauled[sid])
		for def_id: String in RunState.cargo.machine_list():
			if def_id.begins_with("__"):
				RunState.add_to_stock(def_id)
			else:
				RunState.add_machine_instance(def_id)
				RunState.run_stats["machines_hauled"] = int(RunState.run_stats.get("machines_hauled", 0)) + 1
		RunState.cargo.clear()
	if f != null:
		for mi in f.machines.size():
			var cs := f.cache_state(mi)
			if not cs.is_empty() and int(cs.count) > 0 and not _KEPT_IN_INVENTORY.has(String(cs.id)):
				items[String(cs.id)] = int(items.get(String(cs.id), 0)) + f.take_cache(mi)
		for y in f.rows:
			for x in f.cols:
				var pos := Vector2i(x, y)
				var cell := f.get_cell(pos)
				if String(cell.get("kind", "")) != "resource":
					continue
				var id := String(cell.id)
				if _KEPT_IN_INVENTORY.has(id):
					continue  # stays in the base inventory (persists)
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


## Ends the run: banks the haul, and delivers any bridge components toward the lair's survival
## needs. Filling all four needs fires the distress beacon — the rescue (win).
func on_cartridge_shipped(items: Dictionary) -> void:
	RunState.last_run_unlocks = MetaState.bank_delivery(items)
	RunState.needs_delivered = MetaState.deliver_to_needs(items)
	var result := RunState.RESULT_SHIPPED
	if MetaState.lair_restored() and not MetaState.beacon_sent:
		MetaState.send_beacon()
		result = RunState.RESULT_RESCUED
	_end_run(result)


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
	# AUTO-SAVE ON RETURN only (extract / ship / rescue). A LOST run — the bot was destroyed — does NOT
	# save: reloading reverts to your last return, so you forfeit the run's haul + built layout. (Goblin
	# permadeath is saved when it happens, so it stays permanent.) See DESIGN_SPEC §0.2 / roadmap 2.2.
	if result != RunState.RESULT_LOST:
		MetaState.save_factory(RunState.factory)
		MetaState.save_bay(RunState.bay)
		MetaState.save_process(RunState.process_grid)
		MetaState.mark_first_run_done()   # the guide goes quiet after your first successful return
	if player != null:
		player.set_input_locked(true)
	var summary := RunState.end_run(result)
	hud.show_summary(result, summary)
	get_tree().paused = true


func restart_run() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


## Back to the title / main menu (from the end-of-run summary). Autoloads persist, so progress is kept.
func to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/title.tscn")


## DEBUG (F9): wipe the persistent inventory + process line + storage, then reload (a starter line is
## re-seeded on the next launch). Useful for testing the loop from a clean slate.
func debug_reset_to_arm() -> void:
	MetaState.clear_factory()            # bare inventory grid
	MetaState.process_blob = ""          # drop the process lines (a starter line re-seeds on launch)
	MetaState.machine_storage.clear()    # empty the lair storage
	MetaState.machine_instances.clear()  # and the stored machine instances
	MetaState.lair_needs.clear()         # reset the lair's survival needs + beacon
	MetaState.beacon_sent = false
	MetaState.save_game()
	if hud != null:
		hud.log_message("DEBUG: inventory + lines + storage reset.")
	restart_run()
