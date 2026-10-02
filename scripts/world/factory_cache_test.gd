extends Node
## Storage cache: stacks one item type up to capacity from its input, refuses others,
## and take_cache empties it (used when shipping the whole stack in one cartridge slot).
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	var g := FactoryGrid.new(6, 6)
	var mi := g.place_machine_layout("storage_cache", Vector2i(2, 2), [Vector2i(-1, 0)], [], [])
	ck(mi >= 0, "cache placed")
	var inp: Vector2i = g.input_positions(g.machines[mi])[0]
	# feed 3 of the same item
	for i in 3:
		g.set_cell(inp, {"kind": "resource", "id": "scrap_metal"})
		g.tick(0.1)
	var cs := g.cache_state(mi)
	ck(int(cs.count) == 3 and String(cs.id) == "scrap_metal", "stacked 3 items of one type (count=%d)" % int(cs.count))
	# a different item is refused (stays in input)
	g.set_cell(inp, {"kind": "resource", "id": "copper_wire"})
	g.tick(0.1)
	ck(String(g.get_cell(inp).get("id", "")) == "copper_wire" and int(g.cache_state(mi).count) == 3, "different item refused, left in input")
	g.set_cell(inp, {})
	# fill to capacity 16 and stop
	for i in 20:
		g.set_cell(inp, {"kind": "resource", "id": "scrap_metal"})
		g.tick(0.1)
	ck(int(g.cache_state(mi).count) == 16, "caps at capacity 16")
	ck(String(g.get_cell(inp).get("id", "")) == "scrap_metal", "overflow item stays in input when full")
	# moving the cache carries its stack with it
	g.machines[mi]["cached_id"] = "metal_bar"
	g.machines[mi]["cached_count"] = 11
	g.move_machine(mi, Vector2i(4, 4))
	ck(g.is_core(Vector2i(4, 4)), "cache moved to a new cell")
	var moved_cs := g.cache_state(mi)
	ck(String(moved_cs.id) == "metal_bar" and int(moved_cs.count) == 11, "the stack moved with the cache")
	# take_cache empties it and returns the count
	var took := g.take_cache(mi)
	ck(took == 11 and int(g.cache_state(mi).count) == 0, "take_cache returned the stack and emptied")
	if fail == 0: print("CACHE CHECKS PASS")
	else: printerr(fail, " FAIL")
	get_tree().quit(fail)
