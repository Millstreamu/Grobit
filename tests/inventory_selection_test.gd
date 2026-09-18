extends Node


func _ready() -> void:
	RunState.slots.clear()
	for i in RunState.CAPACITY:
		RunState.slots.append({})
	RunState.slots[0] = {"kind": "resource", "id": "raw_scrap"}
	RunState.slots[1] = {"kind": "resource", "id": "raw_scrap"}
	RunState.slots[2] = {"kind": "resource", "id": "electronics"}
	RunState.slots[RunState.CAPACITY - 1] = {
		"kind": "module", "id": "scrap_recycler", "buffer": 0, "progress": 0.0}

	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame

	panel._cursor = 0
	panel._activate()
	panel._cursor = 1
	panel._activate()
	assert(panel._sources == [0, 1])
	assert(panel._cursor_info().contains("x2 selected"))

	# Each activation over the recycler consumes exactly one selected unit.
	panel._cursor = RunState.CAPACITY - 1
	panel._activate()
	assert(panel._sources == [1])
	assert(int(RunState.get_slot(panel._cursor).get("buffer", 0)) == 1)
	panel._activate()
	assert(panel._sources.is_empty())
	assert(int(RunState.get_slot(panel._cursor).get("buffer", 0)) == 2)
	assert(RunState.get_quantity("raw_scrap") == 0)

	print("Inventory stacked-selection tests passed.")
	get_tree().quit()
