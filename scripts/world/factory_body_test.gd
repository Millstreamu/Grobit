extends Node
## Multi-tile machine cores: complex machines occupy several body tiles, placeable/
## interactable from any tile, and the whole body moves together.
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	var g := FactoryGrid.new(8, 8)
	ck(g.core_size_of("smelter") == 1, "a simple machine is 1 tile")
	ck(g.core_size_of("constructor") >= 2, "a complex machine is >1 tile")
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var lay := g.roll_machine_layout("constructor", rng)
	var body: Array = lay.get("body_offsets", [])
	ck(body.size() == g.core_size_of("constructor") - 1, "rolled the right number of extra body tiles")
	var mi := g.place_machine_layout("constructor", Vector2i(4, 4), lay.in_offsets, lay.out_offsets, lay.hold_offsets, body)
	ck(mi >= 0, "placed the multi-tile machine")
	var bcell: Vector2i = Vector2i(4, 4) + body[0]
	ck(String(g.get_cell(bcell).get("kind", "")) == "machine_body", "extra tile is a machine_body cell")
	ck(g.machine_at(bcell) == mi, "machine_at finds it from a body tile (level/move work there)")
	# move to an open spot and confirm the body came along
	var moved := false
	for y in range(0, 8):
		for x in range(0, 8):
			if g.can_relocate(mi, Vector2i(x, y), g.move_offsets(mi)):
				g.move_machine(mi, Vector2i(x, y))
				moved = true
				break
		if moved: break
	var newb: Vector2i = Vector2i(g.machines[mi].core) + body[0]
	ck(moved and String(g.get_cell(newb).get("kind", "")) == "machine_body", "the whole body moved with the core")
	ck(g.get_cell(Vector2i(4, 4)).is_empty() or g.machine_at(Vector2i(4, 4)) == mi, "old body tiles were vacated")
	if fail == 0: print("FACTORY_BODY_TEST: ALL PASS")
	else: printerr("FACTORY_BODY_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
