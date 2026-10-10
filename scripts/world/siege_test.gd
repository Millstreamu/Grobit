extends Node
## Slice 2 — the siege. Harvesting raises an alarm; after a delay the doors are breached and
## besiegers flood in toward the goblins. A goblin they kill is lost for good (permadeath, the
## colony shrinks). Recall + board to flee, which clears the siege. (Movement is engine physics;
## this test drives the siege clock + death LOGIC directly so it's deterministic.)

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	MetaState.seed_colony(3)
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.driving = true

	var bot := Node2D.new()
	add_child(bot)

	var harvest := HarvestMode.new()
	harvest.bot = bot
	add_child(harvest)
	harvest.set_process(false)   # drive the siege clock manually, not via the engine

	harvest.deploy()
	var goblins: Array = get_tree().get_nodes_in_group("harvester_goblins")
	_ck(harvest.active and goblins.size() == 3, "deploy pours out the colony of 3")
	_ck(not harvest.is_breached() and harvest.alarm_ratio() < 1.0, "the alarm starts low (not yet breached)")

	# Harvest long enough and the doors breach.
	harvest.advance_siege(HarvestMode.ALARM_TIME + 0.1)
	_ck(harvest.is_breached(), "after ALARM_TIME the doors are breached")

	# Besiegers then spawn over time.
	for _i in 3:
		harvest.advance_siege(HarvestMode.SPAWN_INTERVAL + 0.01)
	for e: Node in get_tree().get_nodes_in_group("siege_enemies"):
		e.set_physics_process(false)  # freeze them so the test's asserts aren't racing their AI
	_ck(harvest.enemy_count() >= 2, "besiegers flood in after the breach (%d)" % harvest.enemy_count())

	# Permadeath: a goblin the enemies finish off is lost for good — it joins the memorial.
	var doomed := String((goblins[0] as HarvesterGoblin).gob_name)
	(goblins[0] as HarvesterGoblin).take_damage(HarvesterGoblin.MAX_HP)
	_ck(MetaState.colony_size() == 2 and harvest.deployed_count() == 2, "a killed goblin is lost permanently (colony %d)" % MetaState.colony_size())
	_ck(MetaState.fallen.size() == 1 and String(MetaState.fallen[0].get("name", "")) == doomed, "the fallen goblin is named in the memorial (%s)" % doomed)

	# Recall + board the survivors to flee — that ends the siege and clears the besiegers.
	harvest.recall()
	_ck(harvest.recalling, "recall signalled")
	harvest.board(goblins[1])
	harvest.board(goblins[2])
	_ck(not harvest.active and harvest.deployed_count() == 0, "boarding the survivors ends harvest mode")
	_ck(harvest.enemy_count() == 0, "ending the siege clears the besiegers")
	_ck(MetaState.colony_size() == 2, "the one lost goblin stays lost (colony 2)")

	MetaState.seed_colony(3)
	if fail == 0:
		print("SIEGE_TEST: ALL PASS")
	else:
		printerr("SIEGE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
