extends Node
## Phase 4 — the chain PROCESSOR. A valid chain with a scrap-typed intake runs over time: it consumes
## one scrap and makes one product per recipe cycle, blocks when starved, goes idle with no valid chain,
## and re-resolves the product when the line is rearranged mid-run (fluid).

const R := Vector2i(1, 0)
const L := Vector2i(-1, 0)

var fail := 0


## Minimal inventory the processor ticks against.
class FakeInv extends Object:
	var counts := {}
	func get_quantity(id: String) -> int:
		return int(counts.get(id, 0))
	func add(id: String, n: int) -> int:
		counts[id] = int(counts.get(id, 0)) + n
		return n


func _ready() -> void:
	var inv := FakeInv.new()
	inv.counts["steel_scrap"] = 2

	var g := ProcessGrid.new(6, 6)
	g.set_intake(Vector2i(0, 0), R, "steel_scrap")   # feed steel scrap
	g.place("heat", Vector2i(1, 0), L, R)
	g.place("press", Vector2i(2, 0), L, R)            # heat→press = steel_plate (2.5s)
	_ck(g.product_for(g.first_intake()) == "steel_plate", "the line is set up to make steel plate")

	# Partway through a cycle: working, nothing produced yet.
	_ck(not g.tick(1.0, inv), "no product partway through a cycle")
	_ck(g.status == "working", "status is working while it runs")
	_ck(inv.get_quantity("steel_scrap") == 2, "scrap isn't consumed until the cycle completes")

	# Finish the cycle (2.5s total): one scrap in, one plate out.
	_ck(g.tick(2.0, inv), "a completed cycle produces a product")
	_ck(inv.get_quantity("steel_plate") == 1, "one steel plate made")
	_ck(inv.get_quantity("steel_scrap") == 1, "one scrap consumed")

	# Second cycle uses the last scrap, then the line is BLOCKED (starved).
	g.tick(2.5, inv)
	_ck(inv.get_quantity("steel_scrap") == 0 and inv.get_quantity("steel_plate") == 2, "second cycle made a second plate")
	_ck(not g.tick(2.5, inv), "no production with no scrap")
	_ck(g.status == "blocked", "a valid-but-starved line reads as blocked")

	# A broken chain is IDLE and makes nothing even with scrap on hand.
	inv.counts["steel_scrap"] = 5
	g.remove(Vector2i(2, 0))  # break the line (just a Heater now → no recipe for [heat])
	_ck(not g.tick(2.5, inv), "a chain with no recipe produces nothing")
	_ck(g.status == "idle" and inv.get_quantity("steel_scrap") == 5, "no valid recipe → idle, no scrap touched")

	# Fluid: fix the line to a DIFFERENT product and it makes that instead.
	g.place("mold", Vector2i(2, 0), L, R)             # heat→mold = steel_ingot
	g.tick(2.5, inv)
	_ck(inv.get_quantity("steel_ingot") == 1, "rearranged line makes the new product (steel ingot)")

	if fail == 0:
		print("PROCESS_RUN_TEST: ALL PASS")
	else:
		printerr("PROCESS_RUN_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
