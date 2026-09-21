extends Node
## Headless test for conveyors + splitters. Run:
##   godot --headless --path . res://scenes/test/factory_conveyor_test.tscn

const R := Vector2i(1, 0)

func _ready() -> void:
	var failures := 0

	# Straight line: item rides (1,0)->(2,0)->(3,0) then drops onto plain (4,0).
	var g := FactoryGrid.new(6, 3)
	g.place_conveyor(Vector2i(1, 0), R)
	g.place_conveyor(Vector2i(2, 0), R)
	g.place_conveyor(Vector2i(3, 0), R)
	g.get_cell(Vector2i(1, 0))["item"] = "copper"
	g._transport_step()
	failures += _check(String(g.get_cell(Vector2i(2, 0)).get("item", "")) == "copper", "item advances one cell per step")
	failures += _check(String(g.get_cell(Vector2i(1, 0)).get("item", "")) == "", "and leaves the previous cell")
	g._transport_step()
	g._transport_step()
	failures += _check(String(g.get_cell(Vector2i(4, 0)).get("id", "")) == "copper", "item drops onto a plain cell at the end as a resource")

	# Machine -> conveyor -> plain cell: refiner outputs onto a conveyor that carries.
	var g2 := FactoryGrid.new(6, 3)
	g2.place_machine("smelter", Vector2i(1, 0))   # input (0,0), output (2,0)
	g2.place_conveyor(Vector2i(2, 0), R)          # sits on the refiner's output cell
	g2.set_cell(Vector2i(0, 0), {"kind": "resource", "id": "scrap_metal"})
	for _i in 20:
		g2.tick(0.5)
	failures += _check(String(g2.get_cell(Vector2i(3, 0)).get("id", "")) == "metal_bar", "machine output rides a conveyor to a downstream cell")

	# Splitter alternates between its two outputs (right, then down).
	var g3 := FactoryGrid.new(6, 3)
	g3.place_splitter(Vector2i(2, 0), R)          # dir right, dir2 down
	g3.get_cell(Vector2i(2, 0))["item"] = "copper"
	g3._transport_step()
	failures += _check(String(g3.get_cell(Vector2i(3, 0)).get("id", "")) == "copper", "splitter sends first item to primary (right)")
	g3.get_cell(Vector2i(2, 0))["item"] = "copper"
	g3._transport_step()
	failures += _check(String(g3.get_cell(Vector2i(2, 1)).get("id", "")) == "copper", "splitter sends second item to secondary (down)")

	# In-transit items are counted (not lost from the economy).
	var g4 := FactoryGrid.new(4, 2)
	g4.place_conveyor(Vector2i(1, 0), R)
	g4.get_cell(Vector2i(1, 0))["item"] = "wire"
	failures += _check(int(g4.resource_counts().get("wire", 0)) == 1, "items riding conveyors count toward resource totals")

	if failures == 0:
		print("FACTORY_CONVEYOR_TEST: ALL PASS")
	else:
		printerr("FACTORY_CONVEYOR_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
