class_name HarvestMode
extends Node2D
## Drives the deploy / recall / SIEGE beat of a run. Park the bot at a room, [E] to pour the
## colony out to strip it (they haul scrap back to the bot), [E] again to recall. Harvesting
## raises an alarm: after a delay the enemies BREACH the room's doors and flood in, making for
## your goblins. The longer you stay, the more of them. A goblin they reach goes down for good
## (permadeath). Recall + drive away to flee. (Bot auto-turret defense is the next slice.)

const SIEGE_ENEMY := preload("res://scripts/enemies/siege_enemy.gd")
const SPAWNER := preload("res://scripts/enemies/spawner.gd")
const DEPLOY_ACTION := "deploy"
const MAX_SPAWNERS := 3

## Siege pacing (placeholder — tune freely).
const ALARM_TIME := 7.0        # seconds of harvesting before the doors are breached
const SPAWN_INTERVAL := 1.4    # seconds between besiegers once breached
const MAX_ALIVE_BASE := 3      # besiegers alive at once, early
const ESCALATE_EVERY := 8.0    # +1 to that cap every this many seconds after the breach
const HEAT_RISE_PER_SEC := 4.0 # run-wide Heat gained per second while engaged in a breach (Phase 2.1)

var bot: Node2D                 # the player / scrapbot the goblins deploy from and return to
var hud: Node                   # for log messages (optional)
var generator: Node             # AreaGenerator — to find the parked room + its doors

var active := false
var recalling := false
var _goblins: Array = []
var _tasks: Array = []   # commanded targets in PRIORITY (assignment) order; idle goblins flow to these

var _siege_room: Room
var _alarm := 0.0
var _breached := false
var _since_breach := 0.0
var _spawn_accum := 0.0
var _enemies: Array = []
var _spawners: Array = []   # destructible sources placed at the breached doors (Phase 2.4)


func _ready() -> void:
	add_to_group("harvest_mode")


func bot_position() -> Vector2:
	return bot.global_position if bot != null else Vector2.ZERO


## The scrap piles the goblins may strip — ONLY those in the room the bot deployed in (piles are
## children of their room). Falls back to every pile in the scene when there's no room (tests).
func room_piles() -> Array:
	if _siege_room != null:
		var out: Array = []
		for c: Node in _siege_room.get_children():
			if c is ScrapNode:
				out.append(c)
		return out
	return get_tree().get_nodes_in_group("scrap_nodes")


## The broken machines the goblins may repair — ONLY those in the deploy room (pickups are children
## of their room). Falls back to every repairable in the scene when there's no room (tests).
func room_machines() -> Array:
	if _siege_room != null:
		var out: Array = []
		for c: Node in _siege_room.get_children():
			if c is MachinePickup:
				out.append(c)
		return out
	return get_tree().get_nodes_in_group("repairables")


func _process(delta: float) -> void:
	# Deploy / recall input (field only).
	if Input.is_action_just_pressed(DEPLOY_ACTION) and RunState.driving:
		if not active:
			deploy()
		elif not recalling:
			recall()
	if active:
		advance_siege(delta)


# ------------------------------------------------------------- deploy ----

## Pours the colony out around the bot and starts the siege clock for the parked room.
func deploy() -> void:
	if active or bot == null:
		return
	var names: Array = RunState.squad_names()  # the pre-run squad (Scrapbot → Crew), or the whole colony
	if names.is_empty():
		_log("The colony is empty — recruit goblins at the System Terminal before deploying.")
		return
	active = true
	recalling = false
	_tasks.clear()  # goblins start IDLE — nothing is commanded until the player assigns a task
	_siege_room = generator.room_at(bot.global_position) if generator != null and generator.has_method("room_at") else null
	_alarm = 0.0
	_breached = false
	_since_breach = 0.0
	_spawn_accum = 0.0
	var n: int = names.size()
	for i in n:
		var g := HarvesterGoblin.new()
		add_child(g)
		var ang := TAU * float(i) / float(n)
		g.global_position = bot.global_position + Vector2(cos(ang), sin(ang)) * 24.0
		g.gob_name = String(names[i])
		g.tool_tier = maxi(1, MetaState.goblin_tool_tier(String(names[i])))
		g.setup(self)
		_goblins.append(g)
	_log("%d goblins deploy — stripping the room. The noise will draw them in… [E] to recall." % n)


## Signals the goblins to drop everything and return to the bot. New besiegers stop coming.
func recall() -> void:
	if not active or recalling:
		return
	recalling = true
	_log("Recalling the goblins — get back to the bot and drive!")


func board(goblin: Node) -> void:
	_goblins.erase(goblin)
	goblin.queue_free()
	if recalling and _goblins.is_empty():
		_log("All aboard — you got out. Drive on.")
		_end_siege()


## A deployed goblin was killed — permanent loss. It leaves the roster for the memorial.
func on_goblin_lost(goblin: Node) -> void:
	_goblins.erase(goblin)
	var who := String(goblin.gob_name) if goblin.get("gob_name") != null else ""
	MetaState.lose_goblin(who)
	var label := who if who != "" else "A goblin"
	_log("%s fell — the colony is down to %d." % [label, MetaState.colony_size()])
	if _goblins.is_empty():
		_log("The whole party is gone. Nothing left to pull out.")
		_end_siege()


# ------------------------------------------------------------ commands ----

## Command the target under the cursor: register it as a task (priority = first-assigned) and put ONE
## more idle, capable goblin on it. Each call adds one goblin (press F again for more). Returns true
## if a goblin was dispatched (false = nothing free/able to work it, though the task is still queued).
func command_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not _tasks.has(target):
		_tasks.append(target)
	for g: Variant in _goblins:
		if is_instance_valid(g) and g.is_idle() and g.can_work(target):
			g.assigned_target = target
			return true
	return false


## Pull every goblin off `target` (back to idle → they flow to the next task or wait) and drop it.
func cancel_target(target: Node) -> void:
	_tasks.erase(target)
	for g: Variant in _goblins:
		if is_instance_valid(g) and g.assigned_target == target:
			g.assigned_target = null


## Called by an idle goblin: hand it the highest-priority commanded task it can work, if any.
func reassign_idle(goblin: Node) -> void:
	_prune_tasks()
	for t: Variant in _tasks:
		if is_instance_valid(t) and goblin.can_work(t):
			goblin.assigned_target = t
			return


func _prune_tasks() -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if not is_instance_valid(_tasks[i]):
			_tasks.remove_at(i)


func task_count() -> int:
	_prune_tasks()
	return _tasks.size()


## How many goblins are currently on `target` (for the command-cursor readout).
func goblins_on(target: Node) -> int:
	var n := 0
	for g: Variant in _goblins:
		if is_instance_valid(g) and g.assigned_target == target:
			n += 1
	return n


# -------------------------------------------------------------- siege ----

## Advances the alarm + besieger spawns. Call from _process (or a test).
func advance_siege(delta: float) -> void:
	if not active:
		return
	if not _breached:
		_alarm += delta
		if _alarm >= ALARM_TIME:
			_breach()
		return
	if recalling:
		return  # disengaging — no fresh besiegers, just survive the exit
	_since_breach += delta
	_spawn_accum += delta
	_prune_enemies()
	# Heat (presence) climbs while you're seen + engaging — i.e. a breach is live with enemies about.
	# It never decays; it only slows/stops when nothing is engaging you. See DESIGN_SPEC §0.2.
	if not _enemies.is_empty():
		RunState.add_heat(HEAT_RISE_PER_SEC * delta)
	var cap: int = MAX_ALIVE_BASE + int(_since_breach / ESCALATE_EVERY)
	# Besiegers are emitted from the room's SPAWNERS. Wreck them all (below full alert) and the flow
	# stops — that's the pressure relief. On full alert every spawner sources again (hardened).
	if _spawn_accum >= SPAWN_INTERVAL and _enemies.size() < cap:
		_spawn_accum = 0.0
		var src := _pick_source_spawner()
		if src != null:
			_spawn_besieger(src.global_position)


func _breach() -> void:
	_breached = true
	# They force the room's doors open and pour through.
	if _siege_room != null:
		for d: Variant in _siege_room.doors:
			if is_instance_valid(d) and d.has_method("unlock"):
				d.unlock()
	_spawn_spawners()
	_log("They've breached the doors — flooding in! Shoot the spawners to cut the flow. [E] to recall.")


## Plant a destructible spawner at each breached door (capped), the sources besiegers emit from.
func _spawn_spawners() -> void:
	var ps := _door_positions()
	for i in mini(ps.size(), MAX_SPAWNERS):
		var s := SPAWNER.new()
		add_child(s)
		s.global_position = ps[i]
		_spawners.append(s)


## A spawner that can still emit (intact, or any of them on full alert), or null when all are wrecked
## and the facility isn't fully alerted — i.e. the player has cut the flow.
func _pick_source_spawner() -> Node:
	var live: Array = []
	for s: Variant in _spawners:
		if is_instance_valid(s) and s.can_source():
			live.append(s)
	if live.is_empty():
		return null
	return live[randi() % live.size()]


func _spawn_besieger(at: Vector2) -> void:
	var e := SIEGE_ENEMY.new()
	add_child(e)
	e.global_position = at
	e.setup_tier(_roll_enemy_tier())
	_enemies.append(e)


## Picks the besieger tier by Heat (Phase 2.4): calm → only goblin-hunting grunts; once Heat crosses
## HEAT_BOT_THREAT, bruisers that go for the bot start mixing in, more of them at full alert.
func _roll_enemy_tier() -> int:
	match RunState.heat_tier():
		RunState.HEAT_FULL_ALERT_TIER:
			return 2 if randf() < 0.7 else 1
		RunState.HEAT_BOT_THREAT_TIER:
			return 2 if randf() < 0.4 else 1
	return 1


## Ends the siege: clears remaining besiegers and resets the alarm (drove off / wiped).
func _end_siege() -> void:
	for e: Variant in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	for s: Variant in _spawners:
		if is_instance_valid(s):
			s.queue_free()
	_spawners.clear()
	_tasks.clear()
	_alarm = 0.0
	_breached = false
	_since_breach = 0.0
	_spawn_accum = 0.0
	active = false
	recalling = false


func _prune_enemies() -> void:
	for i in range(_enemies.size() - 1, -1, -1):
		if not is_instance_valid(_enemies[i]):
			_enemies.remove_at(i)


## Where besiegers pour in: the parked room's doors, or a fallback point (tests / no room).
func _door_positions() -> Array:
	if _siege_room != null:
		var ps: Array = []
		for d: Variant in _siege_room.doors:
			if is_instance_valid(d):
				ps.append((d as Node2D).global_position)
		if not ps.is_empty():
			return ps
	return [bot_position() + Vector2(120, 0)]


# --------------------------------------------------------- read-outs ----

func deployed_count() -> int:
	return _goblins.size()


func enemy_count() -> int:
	_prune_enemies()
	return _enemies.size()


func is_breached() -> bool:
	return _breached


func alarm_ratio() -> float:
	return clampf(_alarm / ALARM_TIME, 0.0, 1.0) if not _breached else 1.0


func _log(text: String) -> void:
	if hud != null and hud.has_method("log_message"):
		hud.log_message(text)
