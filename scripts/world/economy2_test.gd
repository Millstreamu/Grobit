extends Node
## Headless test for economy batch 2: Grinder→Separator 3-way sort, 3-input Motor,
## Assembler (2× metal_plate), and the fast-vs-efficient recovery difference. Run:
##   godot --headless --path . res://scenes/test/economy2_test.tscn

func _ready() -> void:
	var failures := 0

	# Grinder: broken_motor → mixed_components.
	var g := FactoryGrid.new(6, 4)
	g.place_machine("grinder", Vector2i(1, 1))  # in (0,1), out (2,1)
	g.set_cell(Vector2i(0, 1), {"kind": "resource", "id": "broken_motor"})
	for _i in 8:
		g.tick(0.5)
	failures += _check(String(g.get_cell(Vector2i(2, 1)).get("id", "")) == "mixed_components", "grinder: broken_motor → mixed_components")

	# Separator 3-way sort: mixed_components → scrap_metal + copper_wire + mechanical_parts.
	var g2 := FactoryGrid.new(6, 4)
	g2.place_machine("separator", Vector2i(2, 1))  # out (3,1),(3,2),(3,0)
	g2.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "mixed_components"})
	for _i in 10:
		g2.tick(0.5)
	var got := {}
	for p: Vector2i in [Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 0)]:
		var id := String(g2.get_cell(p).get("id", ""))
		if id != "":
			got[id] = true
	failures += _check(got.has("scrap_metal") and got.has("copper_wire") and got.has("mechanical_parts"), "separator sorts mixed → 3 materials")

	# Fast-vs-efficient: Recycler recovers 2 from a broken motor; Grinder+Separator 3.
	failures += _check(_recycler_yield() == 2 and _grinder_sep_yield() == 3, "efficient recovery (3) beats fast recycler (2)")

	# 3-input Motor on the Constructor (set-based, any arrangement).
	var g3 := FactoryGrid.new(6, 5)
	g3.place_machine("constructor", Vector2i(2, 2))  # inputs (1,2),(2,1),(2,3); out (3,2)
	g3.set_cell(Vector2i(1, 2), {"kind": "resource", "id": "metal_plate"})
	g3.set_cell(Vector2i(2, 1), {"kind": "resource", "id": "refined_copper"})
	g3.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "mechanical_parts"})
	for _i in 14:
		g3.tick(0.5)
	failures += _check(String(g3.get_cell(Vector2i(3, 2)).get("id", "")) == "motor", "constructor: 3 inputs → motor")

	# Assembler needs TWO metal plates + mechanical parts → structural_frame.
	var g4 := FactoryGrid.new(6, 5)
	g4.place_machine("assembler", Vector2i(2, 2))
	g4.set_cell(Vector2i(1, 2), {"kind": "resource", "id": "metal_plate"})
	g4.set_cell(Vector2i(2, 1), {"kind": "resource", "id": "metal_plate"})
	g4.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "mechanical_parts"})
	for _i in 16:
		g4.tick(0.5)
	failures += _check(String(g4.get_cell(Vector2i(3, 2)).get("id", "")) == "structural_frame", "assembler: 2× metal_plate + mechanical_parts → structural_frame")

	if failures == 0:
		print("ECONOMY2_TEST: ALL PASS")
	else:
		printerr("ECONOMY2_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _recycler_yield() -> int:
	var g := FactoryGrid.new(5, 3)
	g.place_machine("scrap_recycler", Vector2i(2, 1))
	g.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "broken_motor"})
	for _i in 8:
		g.tick(0.5)
	var n := 0
	for id: String in g.resource_counts():
		n += int(g.resource_counts()[id])
	return n


func _grinder_sep_yield() -> int:
	# broken_motor → grinder → mixed_components → separator → 3 materials.
	var g := FactoryGrid.new(8, 4)
	g.place_machine("grinder", Vector2i(1, 1))     # out (2,1)
	g.place_machine("separator", Vector2i(3, 1))    # in (2,1); out (4,1),(4,2),(4,0)
	g.set_cell(Vector2i(0, 1), {"kind": "resource", "id": "broken_motor"})
	for _i in 20:
		g.tick(0.5)
	var n := 0
	for id: String in g.resource_counts():
		n += int(g.resource_counts()[id])
	return n


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
