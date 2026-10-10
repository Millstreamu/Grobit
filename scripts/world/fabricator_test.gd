extends Node
## The Fabricator crafts transport parts and caches from resources into stock.

func _ready() -> void:
	var fails := 0
	RunState.factory = FactoryGrid.new(6, 6)
	RunState.machine_stock = {}
	var fp := FabricatorPanel.new()
	add_child(fp)
	# Transport parts are free to craft now (inserts/transport cost nothing).
	fp._cursor = 0
	fp._craft()
	fails += _ck(RunState.stock_count("__conveyor") == 1, "crafting a free conveyor adds it to stock")
	fp._cursor = 2  # filter — also free
	fp._craft()
	fails += _ck(RunState.stock_count("__filter") == 1, "crafting a free filter adds it to stock")
	# A storage cache costs refined copper (3).
	RunState.add("copper", 3)  # into the grid
	fp._cursor = 3  # storage cache
	fp._craft()
	fails += _ck(RunState.stock_count("storage_cache") == 1 and RunState.get_quantity("copper") == 0, "cache crafted, copper spent")
	# Can't craft another cache with no copper left.
	fp._craft()
	fails += _ck(RunState.stock_count("storage_cache") == 1, "can't craft a cache with no resources")
	if fails == 0: print("FABRICATOR_TEST: ALL PASS")
	else: printerr("FABRICATOR_TEST: %d FAIL" % fails)
	get_tree().quit(fails)

func _ck(c: bool, l: String) -> int:
	if c: print("  ok: ", l); return 0
	printerr("  FAIL: ", l); return 1
