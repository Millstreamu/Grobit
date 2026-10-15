extends Node
## The Fabricator crafts SUPPORT MODULES (Phase 4 economy swap: transport parts + caches retired).
## Each module costs base chain products and lands in the bay-module instance storage, ready to equip.

func _ready() -> void:
	var fails := 0
	RunState.factory = FactoryGrid.new(6, 6)
	RunState.machine_instances = []
	var fp := FabricatorPanel.new()
	add_child(fp)

	# Coolant Vent (index 0) costs copper_sheet 2 + plastic_casing 1 — can't craft it broke.
	fp._cursor = 0
	fp._craft()
	fails += _ck(_instances("coolant_module") == 0, "can't craft a module without the products")

	# With the products in the inventory, crafting adds an equippable instance and spends them.
	RunState.add("copper_sheet", 2)
	RunState.add("plastic_casing", 1)
	fp._craft()
	fails += _ck(_instances("coolant_module") == 1, "crafting a module adds a bay-module instance")
	fails += _ck(RunState.get_quantity("copper_sheet") == 0 and RunState.get_quantity("plastic_casing") == 0, "the product cost was spent")

	# Can't craft a second with nothing left.
	fp._craft()
	fails += _ck(_instances("coolant_module") == 1, "can't craft another with no products")

	if fails == 0: print("FABRICATOR_TEST: ALL PASS")
	else: printerr("FABRICATOR_TEST: %d FAIL" % fails)
	get_tree().quit(fails)


func _instances(def_id: String) -> int:
	var n := 0
	for inst: Dictionary in RunState.machine_instances:
		if String(inst.get("def_id", "")) == def_id:
			n += 1
	return n


func _ck(c: bool, l: String) -> int:
	if c: print("  ok: ", l); return 0
	printerr("  FAIL: ", l); return 1
