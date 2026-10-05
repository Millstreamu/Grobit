extends Node
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	# 1. broken recyclers spawn in rooms
	var gen := AreaGenerator.new(); add_child(gen)
	gen.build(GameData.first_area_id(), 999)
	await get_tree().process_frame
	var brokens := 0
	for p in get_tree().get_nodes_in_group("pickups"):
		if p is MachinePickup and p.broken:
			brokens += 1
	ck(brokens > 0, "broken machines spawn in rooms (%d)" % brokens)
	# 2. scrap piles harvest typed scrap into the Scrapper Arm machine's slot (steel = tier 1)
	MetaState.machine_levels = {}  # arm level 1 (steel unlocked)
	var node := ScrapNode.new()
	node.generate({"label":"j","tokens_min":6,"tokens_max":6,"rust_chance":0.0,"pool":[{"id":"steel_scrap","weight":1}]})
	RunState.factory = FactoryGrid.new(8, 8)
	RunState.factory.place_scrapper_arm(Vector2i(0, 0))
	add_child(node)
	node.hold_interact(ScrapNode.HARVEST_SECONDS + 0.1)
	ck(RunState.factory.arm_slot_count("steel_scrap") >= 1, "scrapping stacks typed scrap into the arm")
	# 3. repair a broken recycler -> specialised recycler in stock (paid in refined materials)
	RunState.factory = FactoryGrid.new(8, 8)  # fresh grid for clean accounting
	RunState.machine_instances = []
	RunState.add("copper", 5)  # refined materials live in the grid; repairs spend them
	var mp := MachinePickup.new()
	mp.broken = true; mp.category = "Recycler"; mp.repair_cost = {"copper": 2}
	mp.spec_pool = [{"id":"copper_recycler","weight":1}, {"id":"steel_recycler","weight":1}]
	add_child(mp)
	mp._repair()
	var got := RunState.instance_count()
	var did := String(RunState.machine_instances[0].get("def_id", "")) if got == 1 else ""
	ck(got == 1 and (did == "copper_recycler" or did == "steel_recycler"), "repair specialised into one recycler instance")
	ck(RunState.get_quantity("copper") == 3, "repair spent the refined-material cost")
	# 4. the specialised recycler turns typed scrap into its material
	var f := RunState.factory
	var mi := f.place_machine_layout("copper_recycler", Vector2i(3, 3), [Vector2i(-1, 0)], [Vector2i(1, 0)], [], [])
	f.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "copper_scrap"})
	for _t in 3: f.tick(2.5)
	ck(int(f.resource_counts().get("copper", 0)) > 0, "copper recycler turns copper scrap into copper")
	if fail == 0: print("SLICE1_TEST: ALL PASS")
	else: printerr("SLICE1_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
