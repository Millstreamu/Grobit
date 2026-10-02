extends Node
## Machines are found as world pickups: taking one adds it to the machine stock (ready
## to place free in the factory).

func _ready() -> void:
	var fails := 0
	RunState.machine_stock = {}
	var p := MachinePickup.new()
	p.machine_id = "smelter"
	add_child(p)
	var before := RunState.stock_count("smelter")
	p.interact()
	fails += _ck(RunState.stock_count("smelter") == before + 1, "taking a pickup adds the machine to stock")
	fails += _ck(p.is_queued_for_deletion(), "the pickup is consumed")
	if fails == 0: print("MACHINE_FIND_TEST: ALL PASS")
	else: printerr("MACHINE_FIND_TEST: %d FAIL" % fails)
	get_tree().quit(fails)

func _ck(c: bool, l: String) -> int:
	if c: print("  ok: ", l); return 0
	printerr("  FAIL: ", l); return 1
