extends Node
## Multi-input (set-based) + multi-output recipes. Run:
##   godot --headless --path . res://scenes/test/factory_chain_test.tscn

func _ready() -> void:
	var failures := 0

	# Multi-output: Scrap Recycler turns a Cable Bundle into Copper Wire + Polymer,
	# distributed across its two output cells.
	var g := FactoryGrid.new(5, 4)
	var mi := g.place_machine("scrap_recycler", Vector2i(2, 1))  # in (1,1); out (3,1),(3,2)
	failures += _check(mi >= 0, "recycler placed")
	g.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "cable_bundle"})
	for _i in 8:
		g.tick(0.5)
	var outs := [String(g.get_cell(Vector2i(3, 1)).get("id", "")), String(g.get_cell(Vector2i(3, 2)).get("id", ""))]
	failures += _check(outs.has("copper_wire") and outs.has("polymer"), "multi-output: cable bundle → copper wire + polymer")
	failures += _check(g.get_cell(Vector2i(1, 1)).is_empty(), "recycler input consumed")

	# Multi-input, set-based: Circuit Printer needs electronic_scrap + refined_copper,
	# in EITHER input cell (position doesn't matter).
	var g2 := FactoryGrid.new(6, 3)
	g2.place_machine("circuit_printer", Vector2i(2, 1))  # inputs (1,1),(2,0); out (3,1)
	# Only one input present → no craft.
	g2.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "electronic_scrap"})
	for _i in 12:
		g2.tick(0.5)
	failures += _check(g2.get_cell(Vector2i(3, 1)).is_empty(), "no craft with only one input")
	# Add the second input in the OTHER cell → crafts (set-based).
	g2.set_cell(Vector2i(2, 0), {"kind": "resource", "id": "refined_copper"})
	for _i in 12:
		g2.tick(0.5)
	failures += _check(String(g2.get_cell(Vector2i(3, 1)).get("id", "")) == "circuit_board", "crafts circuit_board with both inputs")

	# Set-based proof: swap which cell holds which input → still crafts.
	var g3 := FactoryGrid.new(6, 3)
	g3.place_machine("circuit_printer", Vector2i(2, 1))
	g3.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "refined_copper"})     # swapped
	g3.set_cell(Vector2i(2, 0), {"kind": "resource", "id": "electronic_scrap"})   # swapped
	for _i in 12:
		g3.tick(0.5)
	failures += _check(String(g3.get_cell(Vector2i(3, 1)).get("id", "")) == "circuit_board", "set-based: swapped inputs still craft")

	# Blocked when there isn't room for all outputs: fill both recycler out cells.
	var g4 := FactoryGrid.new(5, 4)
	g4.place_machine("scrap_recycler", Vector2i(2, 1))
	g4.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "cable_bundle"})
	g4.set_cell(Vector2i(3, 1), {"kind": "resource", "id": "scrap_metal"})
	g4.set_cell(Vector2i(3, 2), {"kind": "resource", "id": "scrap_metal"})
	for _i in 8:
		g4.tick(0.5)
	failures += _check(String(g4.get_cell(Vector2i(1, 1)).get("id", "")) == "cable_bundle", "blocked (no output room): input not consumed")

	if failures == 0:
		print("FACTORY_CHAIN_TEST: ALL PASS")
	else:
		printerr("FACTORY_CHAIN_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
