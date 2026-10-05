extends Node
## Typed scrap economy: a material's scrap pile yields that material's scrap into the Scrapper
## Arm, an adjacent recycler pulls it out and turns it into the base material, and a mismatched
## recycler won't touch it.

var fail := 0


func _ready() -> void:
	# A steel scrap pile harvests steel_scrap into the Scrapper Arm's steel slot (tier 1, the
	# starting tier that's unlocked at arm level 1).
	MetaState.machine_levels = {}  # arm level 1
	RunState.begin_run(GameData.first_area_id(), 7)
	RunState.factory.place_scrapper_arm(Vector2i(0, 0))
	var pile := ScrapNode.new()
	pile.generate({"label": "steel scrap", "tokens_min": 3, "tokens_max": 3,
		"pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(pile)
	pile.hold_interact(ScrapNode.HARVEST_SECONDS + 0.1)
	_ck(RunState.factory.arm_slot_count("steel_scrap") >= 1, "steel pile yields steel scrap into the arm slot")

	# A recycler whose input touches the arm's steel slot PULLS the scrap straight out.
	var armg := FactoryGrid.new(8, 5)
	armg.place_scrapper_arm(Vector2i(0, 0))  # steel slot at (1,0)
	armg.get_cell(Vector2i(1, 0))["count"] = 3
	armg.place_machine("steel_recycler", Vector2i(2, 1))  # input (1,1) is below the steel slot
	for _t in 4: armg.tick(2.5)
	_ck(int(armg.resource_counts().get("steel", 0)) > 0, "a recycler pulls steel scrap from the adjacent arm slot")
	_ck(armg.arm_slot_count("steel_scrap") < 3, "the pull drained the arm slot")

	# The copper recycler turns copper_scrap into copper.
	var f := FactoryGrid.new(8, 8)
	f.place_machine_layout("copper_recycler", Vector2i(3, 3), [Vector2i(-1, 0)], [Vector2i(1, 0)], [], [])
	f.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "copper_scrap"})
	for _t in 3: f.tick(2.5)
	_ck(int(f.resource_counts().get("copper", 0)) > 0, "copper recycler turns copper scrap into copper")

	# A steel recycler will NOT consume copper scrap (wrong input stays put).
	var g := FactoryGrid.new(8, 8)
	g.place_machine_layout("steel_recycler", Vector2i(3, 3), [Vector2i(-1, 0)], [Vector2i(1, 0)], [], [])
	g.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "copper_scrap"})
	for _t in 3: g.tick(2.5)
	_ck(int(g.resource_counts().get("copper_scrap", 0)) == 1, "steel recycler ignores copper scrap")
	_ck(int(g.resource_counts().get("steel", 0)) == 0, "steel recycler produced nothing from the wrong scrap")

	# A recycler won't eat a REFINED material either (only its typed scrap) — it stays put.
	var h := FactoryGrid.new(8, 8)
	h.place_machine_layout("copper_recycler", Vector2i(3, 3), [Vector2i(-1, 0)], [Vector2i(1, 0)], [], [])
	h.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "copper"})
	for _t in 3: h.tick(2.5)
	_ck(int(h.resource_counts().get("copper", 0)) == 1, "recyclers only eat their typed scrap, not refined material")

	if fail == 0:
		print("TYPED_SCRAP_TEST: ALL PASS")
	else:
		printerr("TYPED_SCRAP_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
