extends Node
## Machine storage list: a temporary holding list ([G]) so you can rearrange the grid, but
## the inventory can't be closed until every stored machine is placed (no long-term storage).

var fail := 0


func _ready() -> void:
	var panel := FactoryPanel.new()
	add_child(panel)
	RunState.factory = FactoryGrid.new(8, 8)

	# Empty storage → closing is allowed.
	RunState.machine_stock = {}
	_ck(not panel._has_unplaced(), "empty storage: nothing unplaced")

	# Machines in storage block closing.
	RunState.machine_stock = {"copper_recycler": 2, "steel_ammo_maker": 1}
	_ck(panel._has_unplaced(), "storage with machines: has unplaced")
	_ck(panel._stock_total() == 3, "stock total counts all stored machines")
	_ck(not panel.try_close(), "can't close while machines are in storage")

	# Stash a placed machine into storage (lift it, then [G]).
	var g := FactoryGrid.new(8, 8)
	var mi := g.place_machine("copper_recycler", Vector2i(4, 4))
	RunState.factory = g
	RunState.machine_stock = {}
	panel._reset_modes()
	panel._move_mi = mi
	panel._move_mode = true
	panel._stash_moving_machine()
	_ck(g.machine_at(Vector2i(4, 4)) < 0, "stashed machine leaves the grid")
	_ck(RunState.stock_count("copper_recycler") == 1, "stashed machine goes to storage")
	_ck(not panel._move_mode, "move mode ends after stashing")

	# Retrieve a specific machine from storage into your hand (it stays in stock until dropped).
	RunState.machine_stock = {"steel_recycler": 1}
	panel._reset_modes()
	var ok := panel._begin_place("steel_recycler")
	_ck(ok and panel._place_mode and panel._place_id == "steel_recycler", "retrieve enters place-mode for that machine")
	_ck(RunState.stock_count("steel_recycler") == 1, "retrieved machine stays in storage until actually placed")

	# Transport/caches in stock are NOT counted as unplaced machines (they lay from [B]).
	RunState.machine_stock = {"__conveyor": 3, "storage_cache": 1}
	panel._reset_modes()
	_ck(not panel._has_unplaced(), "transport/caches don't block closing")

	# Once storage is empty, closing works.
	RunState.machine_stock = {}
	_ck(panel.try_close(), "can close once storage is empty")

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
