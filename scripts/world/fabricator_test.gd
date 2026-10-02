extends Node
## The Fabricator crafts transport parts and caches from resources into stock.

func _ready() -> void:
	var fails := 0
	RunState.factory = FactoryGrid.new(6, 6)
	RunState.factory.place_machine("scrapper_arm", Vector2i(0, 0))
	RunState.machine_stock = {}
	RunState.add("junk", 6)
	var fp := FabricatorPanel.new()
	add_child(fp)
	# craft a conveyor (1 junk) and a filter (3 junk)
	fp._cursor = 0
	fp._craft()
	fails += _ck(RunState.stock_count("__conveyor") == 1, "crafting a conveyor adds it to stock")
	fails += _ck(RunState.get_quantity("junk") == 5, "conveyor spent 1 junk from the factory")
	fp._cursor = 2  # filter
	fp._craft()
	fails += _ck(RunState.stock_count("__filter") == 1 and RunState.get_quantity("junk") == 2, "filter crafted, junk spent")
	# can't afford: drain junk, try a cache (3 junk)
	RunState.add("junk", -RunState.get_quantity("junk"))
	fp._cursor = 3  # storage cache
	fp._craft()
	fails += _ck(RunState.stock_count("storage_cache") == 0, "can't craft a cache with no resources")
	if fails == 0: print("FABRICATOR_TEST: ALL PASS")
	else: printerr("FABRICATOR_TEST: %d FAIL" % fails)
	get_tree().quit(fails)

func _ck(c: bool, l: String) -> int:
	if c: print("  ok: ", l); return 0
	printerr("  FAIL: ", l); return 1
