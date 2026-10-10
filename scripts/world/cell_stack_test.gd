extends Node
## In-cell stacking: ammo stacks to 16, tier-1 components to 8, refined materials to 50.
## Machines stack their output, pickup takes the whole stack, and consumers drain stacks.

var fail := 0


func _ready() -> void:
	# Ammo stacks to 16 in a single cell, then spills to a new one.
	var g := FactoryGrid.new(4, 4)
	for _i in 16:
		g.add_resource("charge_cells")
	_ck(_occupied(g) == 1, "16 charge_cells stack into one cell")
	_ck(int(g.resource_counts().get("charge_cells", 0)) == 16, "resource_counts sums the stack")
	g.add_resource("charge_cells")
	_ck(_occupied(g) == 2, "the 17th starts a second stack")

	# Tier-1 components stack to 8.
	var h := FactoryGrid.new(4, 4)
	for _i in 8:
		h.add_resource("power_coupling")
	_ck(_occupied(h) == 1 and int(h.resource_counts().get("power_coupling", 0)) == 8, "components stack to 8")
	h.add_resource("power_coupling")
	_ck(_occupied(h) == 2, "the 9th component starts a second stack")

	# Refined materials stack to 50 (so a material-based economy can hold enough to spend).
	var m := FactoryGrid.new(4, 4)
	for _i in 50:
		m.add_resource("copper")
	_ck(_occupied(m) == 1, "50 copper stack into one cell")
	m.add_resource("copper")
	_ck(_occupied(m) == 2, "the 51st copper starts a second stack")

	# remove_resource drains a stack.
	var r := FactoryGrid.new(4, 4)
	for _i in 5:
		r.add_resource("charge_cells")
	_ck(r.remove_resource("charge_cells", 3) == 3, "remove_resource drains 3 from the stack")
	_ck(int(r.resource_counts().get("charge_cells", 0)) == 2, "2 left after draining")

	# A machine stacks its output into one cell across crafts.
	var a := FactoryGrid.new(6, 6)
	var ai := a.place_machine_layout("copper_ammo_maker", Vector2i(3, 3), [Vector2i(-1, 0), Vector2i(0, -1)], [Vector2i(1, 0)], [], [])
	var ins: Array = a.input_positions(a.machines[ai])
	var outp: Vector2i = a.output_positions(a.machines[ai])[0]
	for _cycle in 2:
		a.set_cell(ins[0], {"kind": "resource", "id": "copper", "count": 1})
		a.set_cell(ins[1], {"kind": "resource", "id": "copper", "count": 1})
		for _t in 3:
			a.tick(2.5)
	_ck(a.cell_count(a.get_cell(outp)) == 2, "a machine stacks its output into one cell")

	if fail == 0:
		print("CELL_STACK_TEST: ALL PASS")
	else:
		printerr("CELL_STACK_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _occupied(g: FactoryGrid) -> int:
	var n := 0
	for y in g.rows:
		for x in g.cols:
			if String(g.get_cell(Vector2i(x, y)).get("kind", "")) == "resource":
				n += 1
	return n


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
