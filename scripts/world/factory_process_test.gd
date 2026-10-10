extends Node
## Headless test for the lair workshop processor: the FactoryProcessor ticks the factory in real
## time while you're at the LAIR (run active, not driving) EVEN WHILE THE TREE IS PAUSED (the
## factory panel pauses the world). Run:
##   godot --headless --path . res://scenes/test/factory_process_test.tscn
## Exits 0 on success. Takes ~4s (real time) because it drives the 3s recipe live.

func _ready() -> void:
	var failures := 0

	# refiner at (2,0) reads (1,0), writes (3,0).
	RunState.factory = FactoryGrid.new(6, 3)
	RunState.factory.place_machine("smelter", Vector2i(2, 0))
	RunState.factory.set_cell(Vector2i(1, 0), {"kind": "resource", "id": "scrap_metal"})
	# Lair phase: a run is set up but you haven't driven out — the workshop refines here.
	RunState.run_active = true
	RunState.driving = false

	add_child(FactoryProcessor.new())

	# Simulate the panel being open: pause the tree. PROCESS_MODE_ALWAYS means the
	# processor keeps running. create_timer defaults to process_always = true.
	get_tree().paused = true
	await get_tree().create_timer(4.0).timeout
	get_tree().paused = false

	var produced := String(RunState.factory.get_cell(Vector2i(3, 0)).get("id", ""))
	failures += _check(produced == "metal_bar", "processor runs while paused: item flowed to output")
	failures += _check(RunState.factory.get_cell(Vector2i(1, 0)).is_empty(), "input consumed during live tick")

	if failures == 0:
		print("FACTORY_PROCESS_TEST: ALL PASS")
	else:
		printerr("FACTORY_PROCESS_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
