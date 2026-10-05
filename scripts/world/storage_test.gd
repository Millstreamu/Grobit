extends Node
## Machine storage ([G]) is a PERSISTENT list of per-instance records (Slice C + C3): each
## found machine keeps its own rolled layout. You place from it (its frozen layout) at setup,
## or leave instances for a later run — closing is always allowed. Transport/caches stay fungible.

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	var panel := FactoryPanel.new()
	add_child(panel)
	RunState.factory = FactoryGrid.new(8, 8)

	# Empty storage.
	RunState.machine_instances = []
	_ck(not panel._has_unplaced(), "empty storage: nothing unplaced")

	# Instances in storage are counted but never block closing.
	RunState.add_machine_instance("copper_recycler")
	RunState.add_machine_instance("copper_recycler")
	RunState.add_machine_instance("steel_ammo_maker")
	_ck(panel._has_unplaced(), "storage with instances: has unplaced")
	_ck(panel._stock_total() == 3, "stock total counts all stored instances")
	_ck(panel.try_close(), "closing is allowed with instances in storage (they persist)")

	# Two copper recyclers should be able to roll DIFFERENT layouts (the point of dupes).
	var a: Dictionary = RunState.machine_instances[0]
	var b: Dictionary = RunState.machine_instances[1]
	_ck(a.has("out_offsets") and b.has("out_offsets"), "each instance carries its own layout")

	# Stash a placed machine → storage, PRESERVING its current layout.
	var g := FactoryGrid.new(8, 8)
	RunState.machine_instances = []
	var mi := g.place_machine_layout("copper_recycler", Vector2i(4, 4), [Vector2i(0, -1)], [Vector2i(0, 1)], [], [])
	RunState.factory = g
	panel._reset_modes()
	panel._move_mi = mi
	panel._move_mode = true
	panel._stash_moving_machine()
	_ck(g.machine_at(Vector2i(4, 4)) < 0, "stashed machine leaves the grid")
	_ck(RunState.instance_count() == 1, "stashed machine goes to storage as an instance")
	_ck(Vector2i(RunState.machine_instances[0]["in_offsets"][0]) == Vector2i(0, -1), "the stashed instance kept its own layout")
	_ck(not panel._move_mode, "move mode ends after stashing")

	# Retrieve that instance into your hand (it stays in storage until actually dropped).
	panel._reset_modes()
	var ok := panel._begin_place_instance(0)
	_ck(ok and panel._place_mode and panel._place_id == "copper_recycler", "retrieve enters place-mode for that instance")
	_ck(RunState.instance_count() == 1, "retrieved instance stays in storage until placed")
	_ck(Vector2i(panel._place_in_offsets[0]) == Vector2i(0, -1), "placing uses the instance's frozen layout (no re-roll)")

	# Transport/caches are fungible counts — never counted as unplaced machines.
	panel._reset_modes()
	RunState.machine_instances = []
	RunState.machine_stock = {"__conveyor": 3, "storage_cache": 1}
	_ck(not panel._has_unplaced(), "transport/caches don't count as unplaced machines")

	if fail == 0:
		print("STORAGE_TEST: ALL PASS")
	else:
		printerr("STORAGE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
