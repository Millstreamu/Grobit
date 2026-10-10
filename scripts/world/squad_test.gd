extends Node
## The pre-run deploy SQUAD (picked in the Scrapbot window's Crew tab at base): RunState tracks which
## goblins ride out, HarvestMode deploys that subset, and an empty pick means "the whole colony".

var fail := 0


func _ready() -> void:
	MetaState.seed_colony(4)
	RunState.begin_run(GameData.first_area_id(), 1)
	var all := MetaState.colony_names()

	# Default: no squad chosen → everyone deploys.
	_ck(RunState.deploy_squad.is_empty(), "a fresh run starts with no explicit squad")
	_ck(RunState.squad_names().size() == 4, "an empty squad means the whole colony deploys")
	_ck(RunState.is_deploying(String(all[0])), "every goblin deploys by default")

	# Toggle one out.
	RunState.toggle_deploy(String(all[0]))
	_ck(not RunState.is_deploying(String(all[0])), "a toggled-off goblin won't deploy")
	_ck(RunState.squad_names().size() == 3, "the squad shrinks to 3")
	_ck(not RunState.squad_names().has(all[0]), "the removed goblin isn't in the squad")

	# Can't empty the squad — always at least one.
	for i in range(1, all.size()):
		RunState.toggle_deploy(String(all[i]))
	_ck(RunState.squad_names().size() == 1, "you can never deploy nobody (floors at 1)")

	# Toggle one back on.
	RunState.toggle_deploy(String(all[0]))
	_ck(RunState.is_deploying(String(all[0])), "a re-added goblin deploys again")

	# begin_run resets the squad.
	RunState.begin_run(GameData.first_area_id(), 1)
	_ck(RunState.deploy_squad.is_empty(), "begin_run clears the squad")
	_ck(RunState.squad_names().size() == MetaState.colony_size(), "the next run defaults to the whole colony again")

	if fail == 0:
		print("SQUAD_TEST: ALL PASS")
	else:
		printerr("SQUAD_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
