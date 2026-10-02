extends Node
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	var f := FactoryGrid.new(8, 8)
	RunState.factory = f
	# 1. a component maker combines two materials into a component
	var mi := f.place_machine_layout("coupling_maker", Vector2i(3, 3), [Vector2i(-1, 0), Vector2i(0, -1)], [Vector2i(1, 0)], [], [])
	ck(mi >= 0, "component maker placed")
	f.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "copper"})
	f.set_cell(Vector2i(3, 2), {"kind": "resource", "id": "steel"})
	for _t in 3: f.tick(3.5)
	ck(int(f.resource_counts().get("power_coupling", 0)) == 1, "coupling maker: copper+steel -> power_coupling")
	# 2. machine type matters: same materials don't make ammo in an ammo maker (needs 2 same)
	var g := FactoryGrid.new(8, 8)
	var ai := g.place_machine_layout("copper_ammo_maker", Vector2i(3, 3), [Vector2i(-1, 0), Vector2i(0, -1)], [Vector2i(1, 0)], [], [])
	g.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "copper"})
	g.set_cell(Vector2i(3, 2), {"kind": "resource", "id": "steel"})
	for _t in 3: g.tick(3.5)
	ck(int(g.resource_counts().get("charge_cells", 0)) == 0, "copper+steel makes NO ammo (ammo needs 2 copper) — machine type matters")
	# 3. broken Component Makers spawn
	var gen := AreaGenerator.new(); add_child(gen)
	gen.build(GameData.first_area_id(), 55)
	await get_tree().process_frame
	var comp := 0
	for p in get_tree().get_nodes_in_group("pickups"):
		if p is MachinePickup and p.broken and p.category == "Component Maker":
			comp += 1
	ck(comp > 0, "broken Component Makers spawn (%d)" % comp)
	if fail == 0: print("SLICE3_TEST: ALL PASS")
	else: printerr("SLICE3_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
