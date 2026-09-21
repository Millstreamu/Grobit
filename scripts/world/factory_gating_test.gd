extends Node
## Placement cost + machine unlock gating. Writes the save (back it up).
## Run: godot --headless --path . res://scenes/test/factory_gating_test.tscn

func _ready() -> void:
	var failures := 0

	# Costs (JSON numbers parse as floats — compare as ints).
	failures += _check(int(RunState.part_cost("smelter").get("scrap_metal", 0)) == 3, "smelter costs scrap_metal 3")
	failures += _check(int(RunState.part_cost("constructor").get("metal_plate", 0)) == 2, "constructor costs metal_plate 2")
	failures += _check(int(RunState.part_cost("__conveyor").get("scrap_metal", 0)) == 1, "conveyor costs scrap_metal 1")
	failures += _check(int(RunState.part_cost("__splitter").get("scrap_metal", 0)) == 2, "splitter costs scrap_metal 2")

	# Gating: the Constructor is locked until circuit boards are delivered.
	MetaState.machines_unlocked.clear()
	MetaState.mars_delivered.clear()
	failures += _check(MetaState.is_machine_unlocked("smelter"), "smelter unlocked by default")
	failures += _check(not MetaState.is_machine_unlocked("constructor"), "constructor locked at first")

	var newly := MetaState.bank_delivery({"circuit_board": 2})
	failures += _check(not MetaState.is_machine_unlocked("constructor"), "still locked below the threshold")
	failures += _check(newly.is_empty(), "no unlock reported below threshold")

	newly = MetaState.bank_delivery({"circuit_board": 1})  # cumulative 3
	failures += _check(MetaState.is_machine_unlocked("constructor"), "constructor unlocks at 3 circuit boards")
	failures += _check(newly.has("Constructor"), "bank_delivery reports the newly unlocked machine")

	MetaState.load_game()
	failures += _check(MetaState.is_machine_unlocked("constructor"), "unlock persists through save/load")

	if failures == 0:
		print("FACTORY_GATING_TEST: ALL PASS")
	else:
		printerr("FACTORY_GATING_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
