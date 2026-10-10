extends Node
## Goblins-do-everything: the bot can't harvest or repair (not player-interactable); goblins repair
## broken machines in the field (paying the cost, taking rarity-scaled time) and HAUL them to the
## bot — lost if the carrier dies mid-haul. Harvest time scales with scrap tier. Tool upgrades are
## bought with the prior tier's refined material. Drives the real goblin logic + economy.

const TICK := 1.0 / 60.0

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	MetaState.seed_colony(1)
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.driving = true
	RunState.machine_instances = []
	RunState.add("steel", 10)  # enough refined material to pay repairs + a tool upgrade

	var bot := Node2D.new()
	add_child(bot)
	bot.global_position = Vector2(500, 0)  # far from the field objects (so hauling takes a trip)
	var harvest := HarvestMode.new()
	harvest.bot = bot
	add_child(harvest)
	harvest.set_process(false)

	# The bot can't touch field objects.
	var pile := ScrapNode.new()
	pile.generate({"tokens_min": 3, "tokens_max": 3, "pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(pile)
	_ck(not pile.can_interact(), "the bot can't harvest a scrap pile")
	var crate := _broken("steel_recycler", {"steel": 2})
	add_child(crate)
	_ck(not crate.can_interact(), "the bot can't repair a broken machine")

	# Rarity → time: a pricier repair takes longer.
	var cheap := _broken("steel_recycler", {"steel": 2})
	var dear := _broken("ceramic_recycler", {"plastic": 4})
	_ck(dear.repair_seconds() > cheap.repair_seconds(), "a pricier machine takes longer to repair (%.1fs vs %.1fs)" % [dear.repair_seconds(), cheap.repair_seconds()])
	cheap.free()
	dear.free()

	# Deploy a goblin; it repairs the crate and hauls it to the bot.
	harvest.deploy()
	var gob: HarvesterGoblin = get_tree().get_nodes_in_group("harvester_goblins")[0]
	_ck(gob.is_idle(), "a deployed goblin is idle until commanded")
	harvest.command_target(crate)  # command it to repair the crate
	var steel_before := RunState.get_quantity("steel")
	var in_hold_before := RunState.cargo.machine_list().size()
	gob.global_position = crate.global_position
	for _i in 600:
		if gob.carrying_machine() != "":
			break
		gob._physics_process(TICK)
	_ck(crate.is_queued_for_deletion(), "the goblin repaired the crate (it's consumed from the field)")
	_ck(RunState.get_quantity("steel") == steel_before - 2, "the repair spent its cost (2 steel)")
	_ck(gob.carrying_machine() == "steel_recycler", "the goblin is now hauling the repaired machine")
	_ck(RunState.cargo.machine_list().size() == in_hold_before, "the machine is NOT in the hold until it reaches the bot")

	# Haul it home: stowed in the cargo hold.
	gob.global_position = bot.global_position
	gob._physics_process(TICK)
	_ck(gob.carrying_machine() == "" and RunState.cargo.machine_list().size() == in_hold_before + 1, "reaching the bot stows the repaired machine in the hold")

	# Lost-on-death: a goblin killed while hauling loses the machine.
	var crate2 := _broken("steel_recycler", {"steel": 2})
	add_child(crate2)
	harvest.command_target(crate2)
	gob.global_position = crate2.global_position
	for _i in 600:
		if gob.carrying_machine() != "":
			break
		gob._physics_process(TICK)
	_ck(gob.carrying_machine() == "steel_recycler", "goblin repaired a second machine and is carrying it")
	var stowed := RunState.cargo.machine_list().size()
	gob.take_damage(HarvesterGoblin.MAX_HP)  # killed mid-haul
	_ck(RunState.cargo.machine_list().size() == stowed, "a carrier killed mid-haul loses the machine (not stowed)")

	# Harvest time scales with tier.
	var g2 := HarvesterGoblin.new()
	var steel_pile := _pile("steel_scrap")   # tier 1
	var ceramic_pile := _pile("ceramic_scrap")  # tier 4
	_ck(g2._harvest_time(ceramic_pile) > g2._harvest_time(steel_pile), "higher-tier scrap takes longer to strip")
	g2.free()
	steel_pile.free()
	ceramic_pile.free()

	# Tool upgrade economy: prior-tier material, self-gating ladder. (Re-seed: the carrier death
	# above emptied this 1-goblin colony.)
	MetaState.seed_colony(1)
	MetaState.unlocked.append("tools_t2")  # higher tool tiers are Tech-Data unlocks now
	MetaState.unlocked.append("tools_t3")
	var who := String(MetaState.colony_names()[0])
	_ck(MetaState.upgrade_tool_cost(who) == {"steel": 3}, "upgrading a tier-1 tool costs steel")
	RunState.spend(MetaState.upgrade_tool_cost(who))
	MetaState.set_goblin_tool(who, MetaState.tool_id_for_tier(2))
	_ck(MetaState.goblin_tool_tier(who) == 2, "the goblin's tool is now tier 2")
	_ck(MetaState.upgrade_tool_cost(who) == {"copper": 3}, "the next upgrade now costs copper (the ladder)")

	MetaState.seed_colony(3)
	MetaState.tools_found.clear()
	if fail == 0:
		print("GOBLIN_WORK_TEST: ALL PASS")
	else:
		printerr("GOBLIN_WORK_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _broken(spec: String, cost: Dictionary) -> MachinePickup:
	var m := MachinePickup.new()
	m.broken = true
	m.spec_pool = [spec]
	m.repair_cost = cost
	return m


func _pile(id: String) -> ScrapNode:
	var n := ScrapNode.new()
	n.generate({"tokens_min": 4, "tokens_max": 4, "pool": [{"id": id, "weight": 1}]})
	return n


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
