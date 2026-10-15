extends Node
## Phase 4 — the hybrid recipe book. Starter recipes (`known:true`) are in the book from the start; the
## rest are hidden until you MAKE them (the processor logs the product the first time). Persisted.

var fail := 0


class FakeInv extends Object:
	var counts := {}
	func get_quantity(id: String) -> int:
		return int(counts.get(id, 0))
	func add(id: String, n: int) -> int:
		counts[id] = int(counts.get(id, 0)) + n
		return n


func _ready() -> void:
	MetaState.discovered_recipes = []

	_ck(MetaState.is_recipe_known("steel_plate"), "a starter (known) recipe is in the book from the start")
	_ck(not MetaState.is_recipe_known("steel_spring"), "a non-starter recipe isn't known until discovered")

	_ck(MetaState.discover_recipe("steel_spring"), "discovering a new recipe logs it")
	_ck(MetaState.is_recipe_known("steel_spring"), "a discovered recipe is now in the book")
	_ck(not MetaState.discover_recipe("steel_spring"), "discovering the same recipe twice is a no-op")
	_ck(not MetaState.discover_recipe("steel_plate"), "a starter-known recipe isn't re-logged")

	var ids: Array = []
	for r: Dictionary in MetaState.known_recipes():
		ids.append(String(r.get("product", "")))
	_ck("steel_plate" in ids, "the book lists starter recipes")
	_ck("steel_spring" in ids, "the book lists discovered recipes")
	_ck(not ("copper_coil" in ids), "the book hides undiscovered non-starter recipes")

	# Running a chain discovers its (non-starter) product via the processor.
	MetaState.discovered_recipes = []
	var inv := FakeInv.new()
	inv.counts["copper_scrap"] = 2
	var g := ProcessGrid.new(5, 5)
	g.set_intake(Vector2i(0, 0), Vector2i(1, 0), "copper_scrap")
	g.place("heat", Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, 0))
	g.place("fold", Vector2i(2, 0), Vector2i(-1, 0), Vector2i(1, 0))  # heat→fold = copper_coil (not known)
	_ck(not MetaState.is_recipe_known("copper_coil"), "copper_coil is unknown before it's made")
	g.tick(3.5, inv)  # completes the 3.0s cycle
	_ck(MetaState.is_recipe_known("copper_coil"), "running the chain discovers copper_coil")

	MetaState.discovered_recipes = []
	if fail == 0:
		print("RECIPE_BOOK_TEST: ALL PASS")
	else:
		printerr("RECIPE_BOOK_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
