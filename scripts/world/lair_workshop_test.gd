extends Node
## Slice 2 — the lair workshop. Refining happens at the LAIR (between runs), not out in the field.
## FactoryProcessor only ticks the factory while you're at the lair (run active, not driving); out
## driving a run it's frozen (the bot carries a cargo hold, not a live factory).

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	RunState.begin_run(GameData.first_area_id(), 1)  # run_active = true, driving = false (lair)
	var f := RunState.factory
	# A steel recycler fed by an adjacent steel-scrap inserter (the refining chain).
	f.place_inserter(Vector2i(1, 0), "steel_scrap")
	f.get_cell(Vector2i(1, 0))["count"] = 6
	f.place_machine("steel_recycler", Vector2i(2, 1))  # input (1,1) sits under the inserter

	var proc := FactoryProcessor.new()
	add_child(proc)

	# Out in the field: the factory is frozen — no refining.
	RunState.driving = true
	for _i in 8:
		proc._process(2.5)
	_ck(int(f.resource_counts().get("steel", 0)) == 0, "the factory does NOT refine while driving a run")

	# Back at the lair: the workshop refines the hauled scrap.
	RunState.driving = false
	for _i in 8:
		proc._process(2.5)
	_ck(int(f.resource_counts().get("steel", 0)) > 0, "the workshop refines scrap at the lair")

	# With the run over, it also stops (nothing to refine between the summary and the next setup).
	var steel_now := int(f.resource_counts().get("steel", 0))
	RunState.run_active = false
	f.get_cell(Vector2i(1, 0))["count"] = 6  # more scrap available…
	for _i in 8:
		proc._process(2.5)
	_ck(int(f.resource_counts().get("steel", 0)) == steel_now, "no refining once the run has ended (not in the lair setup)")

	if fail == 0:
		print("LAIR_WORKSHOP_TEST: ALL PASS")
	else:
		printerr("LAIR_WORKSHOP_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
