extends Node
## Headless test for machine leveling + RNG slots. Run:
##   godot --headless --path . res://scenes/test/factory_level_test.tscn

func _ready() -> void:
	var failures := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var g := FactoryGrid.new(6, 4)
	var mi := g.place_machine("smelter", Vector2i(2, 1))  # input (1,1), output (3,1)
	failures += _check(g.level_of(mi) == 1, "starts at level 1")
	failures += _check(g.machine_at(Vector2i(2, 1)) == mi, "machine_at finds the core")
	failures += _check(g.machine_at(Vector2i(5, 3)) == -1, "machine_at is -1 on empty")

	# Roll a 2-cell shape; it should be the right size and fit, and must not claim
	# the refiner's own input/output cells.
	var shape := g.roll_upgrade(mi, FactoryGrid.SLOTS_PER_LEVEL, rng)
	failures += _check(shape.size() == FactoryGrid.SLOTS_PER_LEVEL, "rolled shape has the right size")
	failures += _check(g.upgrade_fits(shape, FactoryGrid.SLOTS_PER_LEVEL), "rolled shape fits")
	failures += _check(not shape.has(Vector2i(1, 1)) and not shape.has(Vector2i(3, 1)), "shape avoids the machine's I/O cells")

	g.apply_upgrade(mi, shape)
	failures += _check(g.level_of(mi) == 2, "level becomes 2 after upgrade")
	var claimed_ok := true
	for p: Vector2i in shape:
		if not g.is_machine_cell(p):
			claimed_ok = false
	failures += _check(claimed_ok, "slot cells are now claimed (machine_slot)")
	failures += _check(not g.can_place("smelter", shape[0]), "cannot place onto a claimed slot")
	failures += _check(g.upgrade_fits([shape[0]], 1) == false, "upgrade_fits rejects a now-claimed cell")
	failures += _check(g.upgrade_fits([], FactoryGrid.SLOTS_PER_LEVEL) == false, "upgrade_fits rejects a wrong-size shape")

	# Speed: a level-2 refiner (2.4s) beats a level-1 refiner (3.0s). Feed both, tick
	# 2.5s total, and only the leveled one should have produced.
	var mi2 := g.place_machine("smelter", Vector2i(2, 3))  # input (1,3), output (3,3)
	g.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "scrap_metal"})
	g.set_cell(Vector2i(1, 3), {"kind": "resource", "id": "scrap_metal"})
	for _i in 5:
		g.tick(0.5)
	failures += _check(String(g.get_cell(Vector2i(3, 1)).get("id", "")) == "metal_bar", "level-2 machine produced by 2.5s")
	failures += _check(g.get_cell(Vector2i(3, 3)).is_empty(), "level-1 machine not yet done at 2.5s (slower)")

	if failures == 0:
		print("FACTORY_LEVEL_TEST: ALL PASS")
	else:
		printerr("FACTORY_LEVEL_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
