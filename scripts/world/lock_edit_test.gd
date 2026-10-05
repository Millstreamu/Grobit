extends Node
## Slice A: the factory is editable only during setup (in the lair). Once you Accept and drive
## out (RunState.driving), it's locked — read-only, and closing is always allowed.
## Run: godot --headless --path . res://scenes/test/lock_edit_test.tscn

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)
	var panel := FactoryPanel.new()
	add_child(panel)
	await get_tree().process_frame

	# In the lair (not driving) the factory is editable.
	RunState.driving = false
	_ck(panel._editable(), "factory is editable in the lair (setup)")

	# Out in the field (driving) it is locked.
	RunState.driving = true
	_ck(not panel._editable(), "factory is LOCKED once driving (no editing as you go)")

	# Storage persists across runs (Slice C), so a machine left in storage never blocks closing.
	RunState.machine_instances = [{"def_id": "grinder", "in_offsets": [], "out_offsets": [], "hold_offsets": [], "body_offsets": []}]
	RunState.driving = false
	_ck(panel.try_close(), "setup closes even with a machine left in storage (it persists)")
	RunState.driving = true
	_ck(panel.try_close(), "field view always closes (read-only)")

	RunState.machine_instances = []

	# In the field the LAYOUT is locked, but loose items can still be shuffled around the grid.
	RunState.driving = true
	RunState.factory = FactoryGrid.new(8, 8)
	RunState.factory.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "copper", "count": 2})
	panel._cursor = Vector2i(1, 1)
	panel._carried = {}
	panel._pick_or_drop()
	_ck(not panel._carried.is_empty() and int(panel._carried.get("count", 0)) == 2, "items can be picked up and moved even in the field")
	panel._cursor = Vector2i(2, 2)
	panel._pick_or_drop()  # drop one into an empty cell
	_ck(String(RunState.factory.get_cell(Vector2i(2, 2)).get("kind", "")) == "resource", "a carried item drops into an empty field cell")
	panel._carried = {}

	if fail == 0:
		print("LOCK_EDIT_TEST: ALL PASS")
	else:
		printerr("LOCK_EDIT_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
