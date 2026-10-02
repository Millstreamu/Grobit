extends Node
## Typed scrap economy: a material's scrap pile yields that material's scrap, the
## matching recycler turns it into the base material, and a mismatched recycler won't
## touch it. General Junk stays separate (repair/build currency).

var fail := 0


func _ready() -> void:
	# A copper scrap pile harvests copper_scrap into the Scrapper Arm bar.
	RunState.begin_run(GameData.first_area_id(), 7)
	var pile := ScrapNode.new()
	pile.generate({"label": "copper scrap", "tokens_min": 3, "tokens_max": 3,
		"pool": [{"id": "copper_scrap", "weight": 1}]})
	add_child(pile)
	pile.hold_interact(ScrapNode.HARVEST_SECONDS + 0.1)
	_ck(RunState.arm_count("copper_scrap") >= 1, "copper pile yields copper scrap into the arm")

	# A Scrap Insert point pulls copper scrap from the arm into the cell below it.
	var ins := FactoryGrid.new(6, 6)
	RunState.factory = ins
	RunState.arm_scrap["copper_scrap"] = 3
	ins.place_inserter(Vector2i(2, 1), "copper_scrap")
	_ck(String(ins.get_cell(Vector2i(2, 1)).get("kind", "")) == "inserter", "insert point placed")
	for _t in 4: ins.tick(1.0)
	_ck(String(ins.get_cell(Vector2i(2, 2)).get("id", "")) == "copper_scrap", "insert spawns scrap in the cell below")
	_ck(RunState.arm_count("copper_scrap") == 2, "insert pulled one unit from the arm bar")

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

	# General Junk is not a recycler input — it stays as the repair/build currency.
	var h := FactoryGrid.new(8, 8)
	h.place_machine_layout("copper_recycler", Vector2i(3, 3), [Vector2i(-1, 0)], [Vector2i(1, 0)], [], [])
	h.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "junk"})
	for _t in 3: h.tick(2.5)
	_ck(int(h.resource_counts().get("junk", 0)) == 1, "recyclers no longer eat general junk")

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
