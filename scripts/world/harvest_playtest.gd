extends Node
## FULL HARVEST-LOOP PLAYTEST. Not a unit test — a scripted play session that drives the real
## systems (colony roster, HarvestMode deploy/siege, HarvesterGoblin harvest, SiegeEnemy, the
## bot's auto-turret, recruiting) across several runs and narrates what happens. The meta side
## (permadeath, colony size, memorial, recruiting, Tech Data) runs FOR REAL; goblin travel and
## projectile flight are engine physics, so those beats are resolved/narrated here. Ends in a
## handful of invariant checks so it also guards the loop from regressing. Self-quitting.

const TICK := 1.0 / 60.0

var fail := 0
var _bot: Node2D
var _combat: PlayerCombat
var _total_hauled := 0


func _ready() -> void:
	randomize()
	_say("══════════════════════════════════════════════════════════")
	_say("  GROBIT — full harvest-loop playtest")
	_say("══════════════════════════════════════════════════════════")

	# Fresh colony + a bare factory (steel arm only, tier 1).
	MetaState.machine_levels = {}
	MetaState.seed_colony(3)
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.driving = true
	_bot = Node2D.new()
	add_child(_bot)
	_combat = PlayerCombat.new()
	_bot.add_child(_combat)
	_say("\nThe colony wakes: %s." % _roster_line())

	# RUN 1 — the bot has a loaded weapon. Hold the room, defend, extract clean.
	_run(1, true, 2)
	# RUN 2 — no weapon this time. The siege turns costly; recall under fire.
	_run(2, false, 3)
	# Between runs: bank the scrap as Tech Data and recruit a replacement.
	_meta_between_runs()
	# RUN 3 — back to strength, armed again, a confident strip.
	_run(3, true, 2)

	_say("\n──────────────────────── AFTER 3 RUNS ────────────────────────")
	_say("Colony: %s" % _roster_line())
	_say("Memorial: %s" % _memorial_line())
	_say("Total scrap hauled home across the session: %d" % _total_hauled)
	_say("Tech Data on hand: %d" % RunState.get_quantity("tech_data"))

	# Loop invariants — the playtest doubles as an integration guard.
	_ck(MetaState.colony_size() >= 1, "the colony survived the session")
	_ck(MetaState.fallen.size() >= 1, "at least one goblin was lost (run 2 was unarmed)")
	_ck(_total_hauled > 0, "the colony hauled scrap home")
	_ck(MetaState.colony_size() + MetaState.fallen.size() >= 3, "every goblin is accounted for (living + fallen)")
	_ck(_distinct(MetaState.colony_names()), "no duplicate names among the living")

	MetaState.seed_colony(3)
	MetaState.save_game()
	if fail == 0:
		_say("\nHARVEST_PLAYTEST: ALL PASS\n")
	else:
		printerr("HARVEST_PLAYTEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


## One full run: set up a room of scrap, deploy, let the goblins strip it while the alarm climbs,
## survive (or flee) the breach, recall, and tally the haul.
func _run(n: int, armed: bool, waves: int) -> void:
	_say("\n━━━━━━━━━━━━━━━━━━━━ RUN %d ━━━━━━━━━━━━━━━━━━━━" % n)
	_say("The scrapbot rolls out with %d goblins aboard." % MetaState.colony_size())
	_say("Weapon: %s." % ("LOADED — auto-turrets hot" if armed else "none — unarmed, defenceless"))

	# A room of scrap piles around the parked bot.
	var piles: Array = []
	for i in 3:
		var pile := ScrapNode.new()
		pile.generate({"label": "steel", "tokens_min": 12, "tokens_max": 12, "pool": [{"id": "steel_scrap", "weight": 1}]})
		add_child(pile)
		pile.global_position = Vector2(60 + i * 30, (i - 1) * 40)
		piles.append(pile)

	# Arm the bot if this run has a loaded weapon.
	var weapon := -1
	var ammo_slot := Vector2i.ZERO
	if armed:
		weapon = RunState.factory.place_machine("steel_weapon", Vector2i(3, 3))
		ammo_slot = RunState.factory.input_positions(RunState.factory.machines[weapon])[0]
		_reload(ammo_slot)

	var harvest := HarvestMode.new()
	harvest.bot = _bot
	add_child(harvest)
	harvest.set_process(false)  # drive the clock here, not via the engine

	harvest.deploy()
	_say("→ Deploy! %d goblins pour out: %s." % [harvest.deployed_count(), ", ".join(MetaState.colony_names())])
	var goblins := get_tree().get_nodes_in_group("harvester_goblins")

	# They strip piles and haul back — a couple of trips each before the heat arrives.
	var hauled_this_run := _harvest_round(goblins, piles)
	_say("   The goblins strip the piles — %d scrap hauled into the arm so far." % hauled_this_run)

	# The alarm has been climbing the whole time; now the doors give.
	harvest.advance_siege(HarvestMode.ALARM_TIME + 0.1)
	_say("⚠ BREACH — the doors buckle and besiegers flood in!")

	# Waves of besiegers. Armed: turrets cut them down. Unarmed: they reach the goblins.
	for w in waves:
		for _s in 3:
			harvest.advance_siege(HarvestMode.SPAWN_INTERVAL + 0.01)
		var here := _living_besiegers()
		if armed:
			_defend(here, ammo_slot)
			_say("   Wave %d: turrets drop %d besieger(s). Goblins keep working." % [w + 1, here.size()])
			hauled_this_run += _harvest_round(goblins.filter(_alive), piles)
		else:
			# Unarmed, the design is clear: the moment a goblin goes down, signal the rest back
			# and run. A good player eats one loss, not a wipe.
			var casualty := _besiegers_strike(harvest, goblins)
			goblins = goblins.filter(_alive)
			if casualty != "":
				_say("   Wave %d: no return fire — %s is overrun and lost. SIGNAL RETREAT!" % [w + 1, casualty])
				break
			_say("   Wave %d: besiegers close in — pull out NOW." % [w + 1])
			if harvest.deployed_count() == 0:
				break

	# Recall whoever's left and drive clear.
	_say("↩ Recall — survivors sprint for the bot.")
	harvest.recall()
	for g: Node in goblins:
		if _alive(g):
			(g as Node2D).global_position = _bot.global_position
			(g as HarvesterGoblin)._physics_process(TICK)
	_ck(not harvest.active, "run %d: boarding ends harvest mode" % n)
	_say("   Boarded. %d goblins made it back; %d scrap secured this run." % [MetaState.colony_size(), hauled_this_run])
	_total_hauled += hauled_this_run

	# Clean up the run's field objects.
	for pile: Node in piles:
		if is_instance_valid(pile):
			pile.queue_free()
	harvest.queue_free()


## Teleports each living goblin onto the nearest non-empty pile, strips a full load, and deposits
## it at the bot — the real harvest/deposit path. Returns the scrap hauled.
func _harvest_round(goblins: Array, piles: Array) -> int:
	var hauled := 0
	for g: Node in goblins:
		if not _alive(g):
			continue
		var gob := g as HarvesterGoblin
		var pile := _nonempty_pile(piles)
		if pile == null:
			break
		var before := int(RunState.cargo.scrap_counts().get("steel_scrap", 0))
		gob.assigned_target = pile  # goblins are commanded now — put this one on the pile
		gob.global_position = pile.global_position
		for _i in 300:
			gob._physics_process(TICK)
			if gob.carrying() >= HarvesterGoblin.CARRY_CAP:
				break
		gob.global_position = _bot.global_position
		gob._physics_process(TICK)  # deposit into the bot's cargo hold (+ credits the goblin's haul)
		hauled += int(RunState.cargo.scrap_counts().get("steel_scrap", 0)) - before
	return hauled


## Armed defense: the bot actually fires (consuming ammo) and the shots land on the besiegers.
func _defend(besiegers: Array, ammo_slot: Vector2i) -> void:
	for b: Node in besiegers:
		_reload(ammo_slot)             # the factory keeps the turret fed
		_combat.attack_nearest()       # real shot: consumes a round, targets a besieger
		if is_instance_valid(b) and b.has_method("take_damage"):
			b.take_damage(SiegeEnemy.MAX_HP)  # the shot connects


## Unarmed: a besieger finishes off one goblin (real permadeath — the colony shrinks for good).
func _besiegers_strike(harvest: HarvestMode, goblins: Array) -> String:
	for g: Node in goblins:
		if _alive(g):
			var who := String((g as HarvesterGoblin).gob_name)
			(g as HarvesterGoblin).take_damage(HarvesterGoblin.MAX_HP)
			return who
	return ""


## Banks the run's scrap as Tech Data and recruits a replacement for a fallen goblin.
func _meta_between_runs() -> void:
	_say("\n──────────────────── BACK AT THE LAIR ────────────────────")
	RunState.add("food", 40)   # the colony gathered Food out in the ruins
	_say("Gathered Food in the ruins (on hand: %d)." % RunState.get_quantity("food"))
	while MetaState.fallen.size() > 0 and MetaState.can_recruit() and MetaState.colony_size() < 3:
		var cost := int(MetaState.recruit_cost().get("food", 0))
		var rec := MetaState.recruit()
		if rec.is_empty():
			break
		_say("Recruited %s for %d Food — colony now %d strong." % [String(rec.get("name", "?")), cost, MetaState.colony_size()])
	_say("Remembering the lost: %s." % _memorial_line())


# ----------------------------------------------------------- helpers ----

func _reload(slot: Vector2i) -> void:
	RunState.factory.set_cell(slot, {"kind": "resource", "id": "steel_slugs"})


func _alive(g: Node) -> bool:
	return is_instance_valid(g) and not g.is_queued_for_deletion()


func _living_besiegers() -> Array:
	return get_tree().get_nodes_in_group("siege_enemies").filter(_alive)


func _nonempty_pile(piles: Array) -> ScrapNode:
	for p: Node in piles:
		if is_instance_valid(p) and not (p as ScrapNode).is_spent():
			return p
	return null


func _roster_line() -> String:
	var parts: Array = []
	for gdict: Dictionary in MetaState.roster:
		parts.append("%s (%d hauled)" % [String(gdict.get("name", "?")), int(gdict.get("hauled", 0))])
	return ", ".join(parts) if not parts.is_empty() else "(empty)"


func _memorial_line() -> String:
	if MetaState.fallen.is_empty():
		return "(none lost)"
	var parts: Array = []
	for gdict: Dictionary in MetaState.fallen:
		parts.append("%s" % String(gdict.get("name", "?")))
	return ", ".join(parts)


func _distinct(names: Array) -> bool:
	var seen := {}
	for n: Variant in names:
		if seen.has(n):
			return false
		seen[n] = true
	return true


func _say(text: String) -> void:
	print(text)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
