extends Node
## Headless unit test for FactoryGrid core (multi-recipe/multi-output engine). Run:
##   godot --headless --path . res://scenes/test/factory_test.tscn
## Exits 0 on success. Uses the Smelter (scrap_metal -> metal_bar).

func _ready() -> void:
	var failures := 0

	# 5 wide, 4 tall. Smelter: core (2,1), input left (1,1), output right (3,1).
	var g := FactoryGrid.new(5, 4)
	var mi := g.place_machine("smelter", Vector2i(2, 1))
	failures += _check(mi >= 0, "smelter placed")
	failures += _check(g.output_position(g.machines[mi]) == Vector2i(3, 1), "output cell is (3,1)")
	failures += _check(g.input_positions(g.machines[mi]) == [Vector2i(1, 1)], "input cell is (1,1)")

	g.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "scrap_metal"})
	for _i in 10:
		g.tick(0.5)
	failures += _check(_id_at(g, Vector2i(3, 1)) == "metal_bar", "produced metal_bar in output")
	failures += _check(g.get_cell(Vector2i(1, 1)).is_empty(), "input consumed")

	# Blocking: output still full → refill input, it must NOT process.
	g.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "scrap_metal"})
	for _i in 10:
		g.tick(0.5)
	failures += _check(_id_at(g, Vector2i(1, 1)) == "scrap_metal", "blocked while output full: input NOT consumed")

	# Clear output → resumes.
	g.set_cell(Vector2i(3, 1), {})
	for _i in 10:
		g.tick(0.5)
	failures += _check(_id_at(g, Vector2i(3, 1)) == "metal_bar", "resumes after output cleared")

	# Placement rejects overlap and out-of-bounds footprints.
	failures += _check(g.place_machine("smelter", Vector2i(2, 1)) == -1, "reject placing on an existing core")
	failures += _check(g.place_machine("smelter", Vector2i(0, 0)) == -1, "reject when input cell is off-grid")

	# Adjacency chain: scrap placed in a machine's input cell flows through to its output.
	var g2 := FactoryGrid.new(6, 3)
	var sm := g2.place_machine("smelter", Vector2i(2, 0))         # input (1,0), output (3,0)
	failures += _check(sm >= 0, "smelter placed")
	failures += _check(g2.input_positions(g2.machines[sm])[0] == Vector2i(1, 0), "smelter input is the shared cell (1,0)")
	g2.set_cell(Vector2i(1, 0), {"kind": "resource", "id": "scrap_metal"})
	for _i in 10:
		g2.tick(0.5)
	failures += _check(_id_at(g2, Vector2i(3, 0)) == "metal_bar", "item flowed through the smelter to its output")

	if failures == 0:
		print("FACTORY_TEST: ALL PASS")
	else:
		printerr("FACTORY_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _id_at(g: FactoryGrid, p: Vector2i) -> String:
	return String(g.get_cell(p).get("id", ""))


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
