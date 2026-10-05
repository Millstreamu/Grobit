extends Node
## Slice C: machine/transport storage persists across runs. RunState.machine_stock links to
## MetaState.machine_storage, so repairs survive a run and reload from disk.
## Run (writes the save — the runner backs it up): res://scenes/test/storage_persist_test.tscn

var fail := 0


func _ready() -> void:
	# Seed persistent storage, then begin a run: the run's stock/instances should BE the meta's.
	MetaState.machine_storage = {}
	MetaState.machine_instances = []
	RunState.begin_run(GameData.first_area_id(), 1)

	# Repairing a MACHINE adds a per-instance record to the persistent instance list; a conveyor
	# is a fungible count in machine_storage.
	RunState.add_machine_instance("grinder")
	RunState.add_to_stock("__conveyor")
	_ck(MetaState.machine_instances.size() == 1 and String(MetaState.machine_instances[0].get("def_id", "")) == "grinder", "a repaired machine lands in persistent instance storage")
	_ck(int(MetaState.machine_storage.get("__conveyor", 0)) == 1, "a repaired conveyor lands in persistent (fungible) storage")

	# Taking an instance (placing it) removes it from the persistent list.
	RunState.add_machine_instance("steel_recycler")
	RunState.take_instance(RunState.instance_count() - 1)
	_ck(MetaState.machine_instances.size() == 1, "placing an instance removes it from storage")

	# Disk round-trip: save, wipe in memory, reload.
	MetaState.save_game()
	MetaState.machine_storage = {}
	MetaState.machine_instances = []
	MetaState.load_game()
	_ck(MetaState.machine_instances.size() == 1 and String(MetaState.machine_instances[0].get("def_id", "")) == "grinder", "machine instances (with layout) survive save/load")
	_ck(int(MetaState.machine_storage.get("__conveyor", 0)) == 1, "found conveyors survive save/load")

	if fail == 0:
		print("STORAGE_PERSIST_TEST: ALL PASS")
	else:
		printerr("STORAGE_PERSIST_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
