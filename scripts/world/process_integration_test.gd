extends Node
## Phase 4 INTEGRATION — the workshop process line wired into the live run. Verifies that
## RunState.process_grid exists and shares the run inventory, that FactoryProcessor runs the chain ONLY
## at the lair (not while driving), that a made product lands in the inventory and logs a new recipe,
## and that the laid-out line persists through MetaState (save/load_process).

const R := Vector2i(1, 0)
const L := Vector2i(-1, 0)

var fail := 0


func _ready() -> void:
	MetaState.discovered_recipes.clear()
	MetaState.process_blob = ""

	RunState.begin_run("test", 1)
	_ck(RunState.process_grid != null, "begin_run creates a workshop process line")
	_ck(not RunState.driving, "a run starts at the lair (not driving)")

	# Lay a steel_scrap → press → fold → heat line = steel_spring (a NOT-known recipe → discoverable).
	var g: ProcessGrid = RunState.process_grid
	g.set_intake(Vector2i(0, 0), R, "steel_scrap")
	g.place("press", Vector2i(1, 0), L, R)
	g.place("fold", Vector2i(2, 0), L, R)
	g.place("heat", Vector2i(3, 0), L, R)
	_ck(g.product_for(g.first_intake()) == "steel_spring", "the live line resolves to steel spring")
	_ck(not MetaState.is_recipe_known("steel_spring"), "steel spring isn't in the book yet")

	# Scrap goes into the SHARED run inventory (the same grid the player sees).
	RunState.add("steel_scrap", 4)

	# Drive the chain through FactoryProcessor, the real tick path.
	var proc := FactoryProcessor.new()

	# While DRIVING (out in the field), the lair line must not run.
	RunState.driving = true
	var before := RunState.get_quantity("steel_spring")
	proc._process(3.5)
	proc._process(3.5)
	_ck(RunState.get_quantity("steel_spring") == before, "the line does NOT run while driving in the field")
	_ck(RunState.get_quantity("steel_scrap") == 4, "no scrap consumed in the field")

	# Back at the LAIR, the processor runs the chain: scrap in, product out.
	RunState.driving = false
	proc._process(3.5)
	proc._process(3.5)
	_ck(RunState.get_quantity("steel_spring") >= 1, "at the lair the processor made a product into the inventory")
	_ck(RunState.get_quantity("steel_scrap") < 4, "scrap was consumed from the shared inventory")
	_ck(MetaState.is_recipe_known("steel_spring"), "making it the first time logged the recipe (hybrid book)")
	proc.free()

	# Persistence: the laid-out line round-trips through MetaState (var_to_str blob).
	MetaState.save_process(g)
	_ck(MetaState.has_process_line(), "the line persists to the save blob")
	var reloaded := MetaState.load_process()
	_ck(reloaded != null and reloaded.machine_count() == 3, "the reloaded line keeps all its machines")
	_ck(String(reloaded.first_intake().get("scrap", "")) == "steel_scrap", "the reloaded line keeps its intake scrap")
	_ck(reloaded.product_for(reloaded.first_intake()) == "steel_spring", "the reloaded line still makes steel spring")

	MetaState.process_blob = ""  # don't leave test state in the (restored) save

	if fail == 0:
		print("PROCESS_INTEGRATION_TEST: ALL PASS")
	else:
		printerr("PROCESS_INTEGRATION_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
