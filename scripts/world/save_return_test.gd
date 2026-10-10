extends Node
## Phase 2.2 — save-on-return, not on death. A successful RETURN banks the run (saves the factory/
## inventory snapshot); a LOST run (bot destroyed) does NOT save, so reloading reverts to your last
## return — you forfeit the run's haul. This drives the save/revert semantics _end_run relies on.

var fail := 0


func _ready() -> void:
	# Last return: a saved factory holding 5 steel.
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.add("steel", 5)
	MetaState.save_factory(RunState.factory)
	var baseline := MetaState.factory_blob
	_ck(baseline != "", "a return saves a factory snapshot")

	# Next run: reload the snapshot, then gain a big haul out in the field.
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.factory = MetaState.load_factory()
	_ck(RunState.factory != null, "a run rebuilds the saved factory")
	RunState.add("steel", 99)  # the run's gains (now 104 in RunState.factory)

	# BOT DESTROYED → we do NOT save. The snapshot is untouched; a reload reverts to the last return.
	_ck(MetaState.factory_blob == baseline, "a LOST run leaves the saved snapshot unchanged")
	_ck(int(MetaState.load_factory().resource_counts().get("steel", 0)) == 5, "reload after death reverts to the last return (5 steel, not 104)")

	# RETURN instead → saving banks the gains.
	MetaState.save_factory(RunState.factory)
	_ck(MetaState.factory_blob != baseline, "a return updates the snapshot")
	_ck(int(MetaState.load_factory().resource_counts().get("steel", 0)) == 104, "after a return the haul is banked (104 steel)")

	if fail == 0:
		print("SAVE_RETURN_TEST: ALL PASS")
	else:
		printerr("SAVE_RETURN_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
