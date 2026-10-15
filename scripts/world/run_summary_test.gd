extends Node
## Phase 0.3 — the end-of-run summary card's per-run stats. RunState.run_stats tracks scrap hauled,
## machines recovered, goblins lost, and peak Heat (via add_heat), plus recipe discoveries diffed
## against a run-start snapshot — all reset each run in begin_run.

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)
	_ck(int(RunState.run_stats.get("scrap_hauled", -1)) == 0, "a fresh run starts with no haul")
	_ck((RunState.run_stats.get("goblins_lost", []) as Array).is_empty(), "a fresh run has lost no goblins")
	_ck(float(RunState.run_stats.get("heat_peak", -1.0)) == 0.0, "a fresh run has zero peak heat")

	# Peak Heat tracks the high-water mark, not the current value.
	RunState.add_heat(40.0)
	RunState.add_heat(-15.0)   # a Coolant vent lowers current heat but not the peak
	_ck(RunState.heat == 25.0, "current heat reflects the vent")
	_ck(float(RunState.run_stats.get("heat_peak", 0.0)) == 40.0, "peak heat keeps the max reached")

	# Goblin losses are recorded by name for the memorial line.
	RunState.note_goblin_lost("Snik")
	RunState.note_goblin_lost("Borg")
	_ck((RunState.run_stats.get("goblins_lost", []) as Array) == ["Snik", "Borg"], "lost goblins recorded in order")

	# Recipe discoveries this run = book diff vs the run-start snapshot.
	MetaState.discovered_recipes.erase("steel_spring")
	RunState.begin_run(GameData.first_area_id(), 2)   # re-snapshot with steel_spring NOT yet known
	_ck(RunState.recipes_discovered_this_run().is_empty(), "nothing discovered yet this run")
	MetaState.discover_recipe("steel_spring")
	_ck("steel_spring" in RunState.recipes_discovered_this_run(), "discovering a recipe shows up in the run diff")

	# begin_run resets the whole stat block.
	RunState.begin_run(GameData.first_area_id(), 3)
	_ck(int(RunState.run_stats.get("scrap_hauled", -1)) == 0 and (RunState.run_stats.get("goblins_lost", []) as Array).is_empty(), "begin_run clears last run's stats")
	_ck(RunState.recipes_discovered_this_run().is_empty(), "steel_spring now in the snapshot, so not 'this run'")

	MetaState.discovered_recipes.erase("steel_spring")  # leave the book as we found it

	if fail == 0:
		print("RUN_SUMMARY_TEST: ALL PASS")
	else:
		printerr("RUN_SUMMARY_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
