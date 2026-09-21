extends Node
## Step 5 regression: costs read and spend from the factory grid (not a slot bag).
## Run: godot --headless --path . res://scenes/test/build_cost_test.tscn

func _ready() -> void:
	var failures := 0

	RunState.factory = FactoryGrid.new(5, 4)
	RunState.factory.place_machine("scrapper_arm", Vector2i(0, 0))

	RunState.add("scrap_metal", 4)
	RunState.add("electronic_scrap", 1)
	failures += _check(RunState.get_quantity("scrap_metal") == 4, "RunState.add put 4 scrap_metal into the grid")
	failures += _check(RunState.can_afford({"scrap_metal": 3}), "can afford a smelter (scrap_metal:3)")
	failures += _check(not RunState.can_afford({"scrap_metal": 9}), "cannot afford beyond stock")

	failures += _check(RunState.spend({"scrap_metal": 3}), "spend succeeds")
	failures += _check(RunState.get_quantity("scrap_metal") == 1, "spend removed 3 from the grid")
	failures += _check(RunState.get_quantity("electronic_scrap") == 1, "unrelated resource untouched")

	if failures == 0:
		print("BUILD_COST_TEST: ALL PASS")
	else:
		printerr("BUILD_COST_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
