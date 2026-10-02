extends Node
## Scrapper arm: harvested items trickle from holding to a clear output at conveyor
## cadence (built-in conveyor), and its holding+output layout is rolled on build.

func _ready() -> void:
	var fails := 0
	# --- Feed: a held item moves to the free output on a transport step.
	var g := FactoryGrid.new(6, 4)
	var mi := g.place_machine("scrapper_arm", Vector2i(0, 0))
	fails += _ck(mi >= 0, "arm placed at (0,0) with default layout")
	var holds: Array = g.holding_positions(g.machines[mi])
	var outc: Vector2i = g.output_positions(g.machines[mi])[0]
	g.set_cell(holds[0], {"kind": "resource", "id": "bent_panel"})
	g.tick(FactoryGrid.CONVEYOR_INTERVAL)
	fails += _ck(String(g.get_cell(outc).get("id", "")) == "bent_panel", "held item trickled out to the output")
	fails += _ck(g.get_cell(holds[0]).is_empty(), "holding cell emptied after feeding")

	# --- Output blocked: nothing moves while the output cell is occupied.
	g.set_cell(holds[1], {"kind": "resource", "id": "cable_bundle"})
	g.tick(FactoryGrid.CONVEYOR_INTERVAL)  # output (1,0) still holds bent_panel
	fails += _ck(String(g.get_cell(holds[1]).get("id", "")) == "cable_bundle", "held item stays while output is blocked")

	# --- Build roll: arm gets holding + output on distinct orthogonal sides.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var layout := g.roll_machine_layout("scrapper_arm", rng)
	var ho: Array = layout.get("hold_offsets", [])
	var oo: Array = layout.get("out_offsets", [])
	fails += _ck(ho.size() == 3 and oo.size() == 1, "rolled 3 holding + 1 output")
	var seen := {}
	var ortho := true
	for o: Vector2i in ho + oo:
		seen[o] = true
		if abs(o.x) + abs(o.y) != 1:
			ortho = false
	fails += _ck(ortho and seen.size() == 4, "arm ports are on 4 distinct sides")
	var bi := g.place_machine_layout("scrapper_arm", Vector2i(3, 2), [], oo, ho)
	fails += _ck(bi >= 0 and g.hold_offsets_of(g.machines[bi]) == ho, "built arm stores its rolled holding layout")

	if fails == 0:
		print("FACTORY_ARM_TEST: ALL PASS")
	else:
		printerr("FACTORY_ARM_TEST: %d FAIL" % fails)
	get_tree().quit(fails)


func _ck(c: bool, l: String) -> int:
	if c:
		print("  ok: ", l)
		return 0
	printerr("  FAIL: ", l)
	return 1
