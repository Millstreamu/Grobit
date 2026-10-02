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

	# Level no longer affects speed. In a clean grid, a level-2 and a level-1 smelter
	# (both 3.0s) finish at the same time.
	var s := FactoryGrid.new(6, 4)
	var a := s.place_machine("smelter", Vector2i(2, 0))  # input (1,0), output (3,0)
	var b := s.place_machine("smelter", Vector2i(2, 2))  # input (1,2), output (3,2)
	s.level_up_in_place(a)  # a → level 2, b stays level 1
	failures += _check(s.level_of(a) == 2 and s.level_of(b) == 1 and a >= 0 and b >= 0, "two smelters placed, one leveled")
	s.set_cell(Vector2i(1, 0), {"kind": "resource", "id": "scrap_metal"})
	s.set_cell(Vector2i(1, 2), {"kind": "resource", "id": "scrap_metal"})
	for _i in 5:
		s.tick(0.5)  # 2.5s < 3.0s
	failures += _check(s.get_cell(Vector2i(3, 0)).is_empty() and s.get_cell(Vector2i(3, 2)).is_empty(), "level-2 is NOT faster — neither done at 2.5s")
	for _i in 2:
		s.tick(0.5)  # total 3.5s > 3.0s
	failures += _check(String(s.get_cell(Vector2i(3, 0)).get("id", "")) == "metal_bar", "level-2 smelter produces at the normal 3.0s")
	failures += _check(String(s.get_cell(Vector2i(3, 2)).get("id", "")) == "metal_bar", "level-1 smelter produces at the same time")

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
