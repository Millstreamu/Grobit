extends Node
## The tool-based scrapping redesign: no Scrapper Arm. Goblins gate what they scrap by their
## TOOL's tier, only strip the room they deploy in, and their haul feeds the inventory from the
## top-left — or into a scrap inserter pinned to that type. Drives the real data + goblin logic.

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	RunState.begin_run(GameData.first_area_id(), 1)

	# --- deposit_scrap: feeds the grid top-left (row-major), stacking ---
	var f := RunState.factory
	f.deposit_scrap("steel_scrap")
	f.deposit_scrap("steel_scrap")
	var first := f.get_cell(Vector2i(0, 0))
	_ck(String(first.get("kind", "")) == "resource" and String(first.get("id", "")) == "steel_scrap", "scrap fills the top-left cell first")
	_ck(int(first.get("count", 0)) == 2, "a second unit stacks onto the top-left cell")

	# --- an inserter pinned to a type captures that type instead of the grid ---
	f.place_inserter(Vector2i(4, 4), "copper_scrap")
	f.deposit_scrap("copper_scrap")
	f.deposit_scrap("copper_scrap")
	_ck(f.inserter_count("copper_scrap") == 2, "a matching scrap inserter captures the deposit")
	_ck(int(f.resource_counts().get("copper_scrap", 0)) == 0, "the inserter deposit added no loose grid cell")

	# --- a recycler adjacent to an inserter pulls the scrap out ---
	var g := FactoryGrid.new(8, 5)
	g.place_inserter(Vector2i(1, 0), "steel_scrap")
	g.get_cell(Vector2i(1, 0))["count"] = 3
	g.place_machine("steel_recycler", Vector2i(2, 1))  # input (1,1) is below the inserter
	for _t in 4: g.tick(2.5)
	_ck(int(g.resource_counts().get("steel", 0)) > 0, "an adjacent recycler pulls scrap from the inserter")
	_ck(g.inserter_count("steel_scrap") < 3, "the pull drained the inserter")

	# --- the scrapper arm is gone ---
	_ck(not GameData.machines.has("scrapper_arm"), "the scrapper_arm machine no longer exists")

	# --- goblins gate by TOOL tier, and only strip the room they deploy in ---
	MetaState.seed_colony(1)                      # one goblin, tier-1 (steel) starter tool
	var mode := HarvestMode.new()
	var bot := Node2D.new()
	add_child(bot)
	mode.bot = bot
	add_child(mode)
	mode.deploy()
	var gob: HarvesterGoblin = get_tree().get_nodes_in_group("harvester_goblins")[0]
	_ck(gob.tool_tier == 1, "a starter goblin deploys with a tier-1 tool")

	var steel_pile := _pile("steel_scrap")
	var copper_pile := _pile("copper_scrap")
	add_child(steel_pile)
	add_child(copper_pile)
	_ck(gob._valid(steel_pile), "a tier-1 goblin can scrap a steel pile")
	_ck(not gob._valid(copper_pile), "a tier-1 goblin can NOT scrap a copper pile (tool too weak)")

	# A better tool lifts the gate.
	gob.tool_tier = 2
	_ck(gob._valid(copper_pile), "with a tier-2 tool the goblin can now scrap copper")

	# equip_tool swaps a found tool onto a goblin and raises the colony frontier.
	MetaState.seed_colony(1)
	MetaState.found_tool("copper_cutter")
	var who := String(MetaState.colony_names()[0])
	_ck(MetaState.equip_tool(who, "copper_cutter"), "a found tool equips onto a goblin")
	_ck(MetaState.goblin_tool_tier(who) == 2 and MetaState.best_tool_tier() == 2, "the equipped tool raises the goblin's reach + the frontier")

	MetaState.seed_colony(3)
	if fail == 0:
		print("SCRAP_TOOLS_TEST: ALL PASS")
	else:
		printerr("SCRAP_TOOLS_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


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
