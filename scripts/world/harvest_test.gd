extends Node
## Slice 1 — deploy & auto-harvest. A deployed colony goblin autonomously strips a scrap pile and
## hauls it back to the bot's Scrapper Arm; recall re-boards it. (Movement is engine physics, so
## this test teleports the goblin between its targets and verifies the harvest/deposit/recall
## LOGIC deterministically — travel itself is exercised in-game.)

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	MetaState.seed_colony(1)  # one goblin with the tier-1 (steel) tool
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.driving = true

	var bot := Node2D.new()
	add_child(bot)
	bot.global_position = Vector2(0, 0)

	var pile := ScrapNode.new()
	pile.generate({"label": "steel", "tokens_min": 10, "tokens_max": 10, "pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(pile)
	pile.global_position = Vector2(48, 0)

	var harvest := HarvestMode.new()
	harvest.bot = bot
	add_child(harvest)

	harvest.deploy()
	_ck(harvest.active and harvest.deployed_count() == 1, "deploy pours out the colony")
	var g: HarvesterGoblin = get_tree().get_nodes_in_group("harvester_goblins")[0]
	harvest.command_target(pile)  # goblins are commanded now — put it on the pile

	# At the pile: it strips a load (CARRY_CAP pieces), then switches to returning.
	g.global_position = pile.global_position
	for _i in 300:
		g._physics_process(1.0 / 60.0)
		if g.carrying() >= HarvesterGoblin.CARRY_CAP:
			break
	_ck(g.carrying() == HarvesterGoblin.CARRY_CAP, "goblin strips a full load off the pile (%d)" % g.carrying())
	_ck(pile.tokens == 10 - HarvesterGoblin.CARRY_CAP, "the pile was depleted by what it took (%d left)" % pile.tokens)

	# Back at the bot: the load feeds into the inventory grid (top-left).
	g.global_position = bot.global_position
	g._physics_process(1.0 / 60.0)
	var steel := int(RunState.cargo.scrap_counts().get("steel_scrap", 0))
	_ck(steel == HarvesterGoblin.CARRY_CAP, "the haul lands in the bot's cargo hold (%d)" % steel)
	_ck(g.carrying() == 0, "goblin is empty-handed after depositing")

	# Regression: a pile the goblin strips EMPTY frees itself. The goblin still holds it as its
	# target, so the next tick runs _valid() on a freed object — which crashes if the parameter is
	# typed ScrapNode. Force that exact state and prove the goblin shrugs it off and re-seeks.
	var empty := ScrapNode.new()
	empty.generate({"label": "steel", "tokens_min": 1, "tokens_max": 1, "pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(empty)
	empty.global_position = bot.global_position + Vector2(40, 0)
	g._target = empty
	g.assigned_target = empty   # its commanded target is the one that gets freed
	empty.take_one()   # empties the pile (queue_free is deferred in headless)
	empty.free()       # force the freed state deterministically
	g._physics_process(1.0 / 60.0)  # can_work/_valid(freed): must not crash
	_ck(is_instance_valid(g), "goblin survives a target pile freed mid-harvest (no crash)")

	# Recall: at the bot it re-boards and harvest mode ends.
	harvest.recall()
	_ck(harvest.recalling, "recall signalled")
	g.global_position = bot.global_position
	g._physics_process(1.0 / 60.0)
	_ck(not harvest.active and harvest.deployed_count() == 0, "goblin re-boarded; harvest mode ended")
	_ck(g.is_queued_for_deletion(), "the re-boarded goblin is freed")

	if fail == 0:
		print("HARVEST_TEST: ALL PASS")
	else:
		printerr("HARVEST_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
