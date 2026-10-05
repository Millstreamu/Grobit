extends Node
## Machines are found as world pickups: taking one adds a per-instance record (with its own
## rolled layout) to machine storage, ready to place at a run's setup.

func _ready() -> void:
	var fails := 0
	RunState.machine_instances = []
	var p := MachinePickup.new()
	p.machine_id = "smelter"
	add_child(p)
	var before := RunState.instance_count()
	p.interact()
	fails += _ck(RunState.instance_count() == before + 1, "taking a pickup adds a machine instance to storage")
	fails += _ck(String(RunState.machine_instances[-1].get("def_id", "")) == "smelter", "the stored instance is the smelter")
	fails += _ck(p.is_queued_for_deletion(), "the pickup is consumed")
	if fails == 0: print("MACHINE_FIND_TEST: ALL PASS")
	else: printerr("MACHINE_FIND_TEST: %d FAIL" % fails)
	get_tree().quit(fails)

func _ck(c: bool, l: String) -> int:
	if c: print("  ok: ", l); return 0
	printerr("  FAIL: ", l); return 1
