extends Node
## Persistent factory: the LAYOUT (machines, transport, inserters) AND the base inventory (loose
## resources + cache contents) survive a save/load round-trip — what the colony hauls home stays
## in your base. Only in-transit state (items riding belts) and in-flight progress reset. MetaState
## carries it all as a var_to_str blob.

var fail := 0


func _ready() -> void:
	var g := FactoryGrid.new(8, 8)
	g.place_machine("copper_recycler", Vector2i(3, 3))
	g.place_conveyor(Vector2i(5, 5), Vector2i(1, 0))
	g.get_cell(Vector2i(5, 5))["item"] = "copper"  # riding a belt — shouldn't persist (in-transit)
	g.set_cell(Vector2i(2, 2), {"kind": "resource", "id": "copper", "count": 3})  # base inventory — persists
	var ci := g.place_machine("storage_cache", Vector2i(6, 1))
	g.machines[ci]["cached_count"] = 9
	g.machines[ci]["cached_id"] = "copper"

	# Full round-trip through the exact serialization MetaState uses.
	var blob := var_to_str(g.to_data())
	var g2 := FactoryGrid.from_data(str_to_var(blob))

	_ck(g2.cols == 8 and g2.rows == 8, "grid dimensions preserved")
	_ck(g2.machine_at(Vector2i(3, 3)) >= 0, "a placed machine persists")
	_ck(String(g2.get_cell(Vector2i(5, 5)).get("kind", "")) == "conveyor", "a conveyor persists")
	_ck(String(g2.get_cell(Vector2i(5, 5)).get("item", "")) == "", "an item riding a belt does NOT persist (in-transit)")
	_ck(String(g2.get_cell(Vector2i(2, 2)).get("id", "")) == "copper" and int(g2.get_cell(Vector2i(2, 2)).get("count", 0)) == 3, "base-inventory resources persist")
	_ck(int(g2.cache_state(g2.machine_at(Vector2i(6, 1))).get("count", -1)) == 9, "cache contents persist")

	# The reloaded recycler still processes (its recipe wiring survives).
	g2.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "copper_scrap"})  # its input (core + [-1,0])
	for _t in 3:
		g2.tick(2.5)
	_ck(int(g2.resource_counts().get("copper", 0)) > 0, "a reloaded recycler still works")

	# MetaState carries the blob (in-memory path — no disk writes in the test).
	MetaState.factory_blob = blob
	_ck(MetaState.has_factory(), "has_factory is true when a blob is set")
	var g3 := MetaState.load_factory()
	_ck(g3 != null and g3.machine_at(Vector2i(3, 3)) >= 0, "MetaState.load_factory rebuilds the layout")

	# Mirror the RunController flow: begin_run() makes a bare grid, then the saved layout
	# replaces it, so a new run inherits your factory.
	RunState.begin_run(GameData.first_area_id(), 1)
	if MetaState.has_factory():
		RunState.factory = MetaState.load_factory()
	_ck(RunState.factory.machine_at(Vector2i(3, 3)) >= 0, "a new run inherits the persisted factory")

	MetaState.factory_blob = ""
	_ck(not MetaState.has_factory() and MetaState.load_factory() == null, "a cleared blob means no factory")

	if fail == 0:
		print("PERSISTENCE_TEST: ALL PASS")
	else:
		printerr("PERSISTENCE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
