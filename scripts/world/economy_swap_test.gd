extends Node
## Phase 4 economy swap — end to end. The process lines are the whole economy now: chains turn scrap
## into base products (the upgrade/build currency), ammo (fed to weapons), and components (lair needs).
## Builds a THREE-line grid, ticks it against the shared inventory, then spends each product in its role.

const R := Vector2i(1, 0)
const L := Vector2i(-1, 0)

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)

	var g := RunState.process_grid
	# Line 1: steel_scrap → heat → press = steel_plate (base product / currency).
	g.set_intake(Vector2i(0, 0), R, "steel_scrap")
	g.place("heat", Vector2i(1, 0), L, R)
	g.place("press", Vector2i(2, 0), L, R)
	# Line 2: copper_scrap → press → heat = charge_cells (ammo).
	g.set_intake(Vector2i(0, 2), R, "copper_scrap")
	g.place("press", Vector2i(1, 2), L, R)
	g.place("heat", Vector2i(2, 2), L, R)
	# Line 3: steel_scrap → fold → press = reinforced_frame (a lair-need component).
	g.set_intake(Vector2i(0, 4), R, "steel_scrap")
	g.place("fold", Vector2i(1, 4), L, R)
	g.place("press", Vector2i(2, 4), L, R)
	_ck(g.intake_count() == 3, "three parallel production lines")

	# Feed the shared inventory and run the lines (as FactoryProcessor would, at the lair).
	RunState.add("steel_scrap", 20)
	RunState.add("copper_scrap", 10)
	for _i in 12:
		g.tick(4.0, RunState)

	var plate := RunState.get_quantity("steel_plate")
	var ammo := RunState.get_quantity("charge_cells")
	var frame := RunState.get_quantity("reinforced_frame")
	_ck(plate >= 3, "the lines produced steel plate (currency): %d" % plate)
	_ck(ammo >= 1, "the lines produced charge cells (ammo): %d" % ammo)
	_ck(frame >= 1, "the lines produced reinforced frames (component): %d" % frame)

	# ROLE 1 — currency: a tier-1 tool upgrade is paid in steel plate.
	MetaState.seed_colony(1)
	MetaState.unlocked = ["tools_t2"]
	var who := String(MetaState.colony_names()[0])
	_ck(MetaState.upgrade_tool_cost(who) == {"steel_plate": 3}, "a tool upgrade costs steel plate (a product)")
	_ck(RunState.can_afford(MetaState.upgrade_tool_cost(who)), "the plate we made covers the upgrade")
	RunState.spend(MetaState.upgrade_tool_cost(who))
	MetaState.set_goblin_tool(who, MetaState.tool_id_for_tier(2))
	_ck(MetaState.goblin_tool_tier(who) == 2, "spending the product upgraded the tool")

	# ROLE 2 — ammo: a bay weapon loads the chain-made charge cells onto the bot.
	RunState.bay = FactoryGrid.new(RunState.BAY_COLS, RunState.BAY_ROWS)
	RunState.bay.place_machine("copper_weapon", Vector2i(0, 0))  # ammo = charge_cells
	RunState.load_ammo()
	_ck(RunState.ammo_count("charge_cells") >= 1, "load_ammo pulls the chain-made ammo onto the bot")
	_ck(RunState.consume_ammo("charge_cells"), "the weapon can fire a chain-made round")

	# ROLE 3 — lair need: a chain-made component fills the oxygen need.
	MetaState.lair_needs = {}
	var before := MetaState.need_amount("oxygen")
	MetaState.deliver_to_needs({"reinforced_frame": frame})
	_ck(MetaState.need_amount("oxygen") > before, "a chain-made component fills a lair need")

	MetaState.lair_needs = {}
	MetaState.unlocked = []

	if fail == 0:
		print("ECONOMY_SWAP_TEST: ALL PASS")
	else:
		printerr("ECONOMY_SWAP_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
