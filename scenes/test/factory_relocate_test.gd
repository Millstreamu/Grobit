extends Node
## Regression test for level-up relocation (a machine's upgrade footprint can be
## moved to where it fits, keeping modules/connections) and for placing conveyors /
## machine cores over loose items (the item is shifted aside, not blocked).

var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_fail += 1
		printerr("  FAIL: ", label)


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	# --- roll_upgrade_offsets returns a full connected shape regardless of occupancy ---
	var f := FactoryGrid.new(6, 6)
	var mi := f.place_machine("smelter", Vector2i(2, 2))
	# Box the smelter in with resource items on all sides.
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		f.set_cell(Vector2i(2, 2) + d, {"kind": "resource", "id": "scrap_metal"})
	var offs := f.roll_upgrade_offsets(mi, FactoryGrid.SLOTS_PER_LEVEL, rng)
	_check(offs.size() == FactoryGrid.SLOTS_PER_LEVEL, "rolled full slot shape even when boxed in")

	# --- can_relocate: false where blocked by machine cells, true in open space ---
	# (Placed away from the left edge so the smelter's [-1,0] input stays in bounds.)
	var f2 := FactoryGrid.new(6, 6)
	var a := f2.place_machine("smelter", Vector2i(2, 2))
	var other := f2.place_machine("press", Vector2i(4, 4))
	_check(a >= 0 and other >= 0, "both machines placed")
	# A vertical new-slot shape that avoids the smelter's horizontal in/out offsets.
	var shape := [Vector2i(0, 1), Vector2i(0, 2)]
	_check(not f2.can_relocate(a, Vector2i(4, 4), [Vector2i(0, 1)]), "can't relocate onto another machine")
	_check(f2.can_relocate(a, Vector2i(3, 3), shape), "can relocate into open space")

	# --- relocate_upgraded moves the machine, bumps level, remaps a module ---
	var f3 := FactoryGrid.new(6, 6)
	var b := f3.place_machine("smelter", Vector2i(2, 2))
	f3.apply_upgrade(b, [Vector2i(2, 3)])  # give it one existing slot below the core
	f3.install_module(Vector2i(2, 3), "overclock")
	var lvl_before := f3.level_of(b)
	# Full offsets: existing (0,1) + a new slot (1,1); move core (2,2) -> (4,4), delta (2,2).
	f3.relocate_upgraded(b, Vector2i(4, 4), [Vector2i(0, 1), Vector2i(1, 1)])
	_check(f3.is_core(Vector2i(4, 4)), "core moved to new position")
	_check(f3.get_cell(Vector2i(2, 2)).is_empty(), "old core cell cleared")
	_check(f3.level_of(b) == lvl_before + 1, "level bumped")
	_check(f3.module_at(Vector2i(4, 5)) == "overclock", "module followed its slot (delta remap)")

	# --- move_machine relocates without changing level, keeping its module ---
	var fm := FactoryGrid.new(6, 6)
	var mv := fm.place_machine("smelter", Vector2i(2, 2))
	fm.apply_upgrade(mv, [Vector2i(2, 3)])
	fm.install_module(Vector2i(2, 3), "overclock")
	var lvl := fm.level_of(mv)
	_check(fm.can_relocate(mv, Vector2i(4, 4), fm.move_offsets(mv)), "can move to open space")
	fm.move_machine(mv, Vector2i(4, 4))
	_check(fm.is_core(Vector2i(4, 4)), "moved core to new position")
	_check(fm.get_cell(Vector2i(2, 2)).is_empty(), "old core cleared after move")
	_check(fm.level_of(mv) == lvl, "move does NOT change level")
	_check(fm.module_at(Vector2i(4, 5)) == "overclock", "module followed the moved slot")

	# --- Build layout: ports are rolled per instance, connected to the core ---
	var fb := FactoryGrid.new(6, 6)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	var bdef: Dictionary = GameData.machines.get("smelter", {})
	var layout := fb.roll_machine_layout("smelter", rng2)
	var ins: Array = layout.get("in_offsets", [])
	var outs: Array = layout.get("out_offsets", [])
	_check(ins.size() == (bdef.get("inputs", []) as Array).size() and outs.size() == (bdef.get("outputs", []) as Array).size(), "rolled layout matches the def's port counts")
	var orthogonal := true
	var distinct := {}
	for o: Vector2i in ins + outs:
		distinct[o] = true
		if abs(o.x) + abs(o.y) != 1:  # Manhattan distance 1 = a direct side, no diagonal
			orthogonal = false
	_check(orthogonal, "every port is on a direct side of the core (no diagonals)")
	_check(distinct.size() == ins.size() + outs.size(), "ports never overlap each other")
	var bi := fb.place_machine_layout("smelter", Vector2i(2, 2), ins, outs)
	_check(bi >= 0, "machine placed with its rolled layout")
	_check(fb.in_offsets_of(fb.machines[bi]) == ins, "input_positions reads the stored instance layout")

	# --- conveyor placement shifts a loose item aside instead of blocking ---
	var f4 := FactoryGrid.new(4, 4)
	f4.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "scrap_metal"})
	var ok := f4.place_conveyor(Vector2i(1, 1), Vector2i(1, 0))
	_check(ok, "conveyor placed over an item")
	_check(String(f4.get_cell(Vector2i(1, 1)).get("kind", "")) == "conveyor", "cell is now a conveyor")
	_check(f4.resource_counts().get("scrap_metal", 0) == 1, "the displaced item was preserved")

	# --- machine core placement shifts a loose item aside ---
	var f5 := FactoryGrid.new(4, 4)
	f5.set_cell(Vector2i(2, 2), {"kind": "resource", "id": "scrap_metal"})
	var c := f5.place_machine("smelter", Vector2i(2, 2))
	_check(c >= 0, "machine placed over an item on its core")
	_check(f5.resource_counts().get("scrap_metal", 0) == 1, "the covered item was preserved")

	if _fail == 0:
		print("ALL RELOCATE CHECKS PASSED")
	else:
		printerr(_fail, " CHECK(S) FAILED")
	get_tree().quit(_fail)
