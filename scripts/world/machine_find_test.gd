extends Node
## Machines are found BROKEN in the field; a goblin repairs one (repair_and_take spends the cost)
## and banks it as a per-instance record (with its own rolled layout) in machine storage.

func _ready() -> void:
	var fails := 0
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.machine_instances = []
	var p := MachinePickup.new()
	p.broken = true
	p.spec_pool = ["smelter"]
	p.repair_cost = {}  # free to repair for this unit test
	add_child(p)
	var before := RunState.instance_count()
	var repaired := p.repair_and_take()            # the goblin's repair step…
	RunState.add_machine_instance(repaired)         # …and its bank-at-bot step
	fails += _ck(RunState.instance_count() == before + 1, "repairing a found machine adds an instance to storage")
	fails += _ck(String(RunState.machine_instances[-1].get("def_id", "")) == "smelter", "the stored instance is the smelter")
	fails += _ck(p.is_queued_for_deletion(), "the repaired pickup is consumed from the field")
	if fails == 0: print("MACHINE_FIND_TEST: ALL PASS")
	else: printerr("MACHINE_FIND_TEST: %d FAIL" % fails)
	get_tree().quit(fails)

func _ck(c: bool, l: String) -> int:
	if c: print("  ok: ", l); return 0
	printerr("  FAIL: ", l); return 1
