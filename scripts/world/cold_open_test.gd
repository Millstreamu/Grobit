extends Node
## Phase 6 — cold open & onboarding (data layer). Intro quests load and their new goal types read the
## right sources; New Game wipes the save to a fresh colony; Debug Lair pre-stocks a test game; and the
## guided-run nudge gate fires once then goes quiet (and never after the first run). The title screen +
## scene transitions + the in-world debug bootstrap are exercised by the full-game boot + screenshots.

var fail := 0


func _ready() -> void:
	# Intro quests + their new goal types.
	_ck(not _quest("intro_recruit").is_empty() and not _quest("intro_build").is_empty() and not _quest("intro_craft").is_empty(), "the three intro quests load")
	MetaState.lair_stations = [{"type": "workshop", "x": 0, "y": 0}, {"type": "missions", "x": 1, "y": 0}]
	_ck(MetaState.quest_current({"type": "stations"}) == 2, "'stations' goal reads the lair-station count")
	MetaState.discovered_recipes = ["steel_spring"]
	_ck(MetaState.quest_current({"type": "recipes"}) == 1, "'recipes' goal reads the discovered-recipe count")

	# New Game wipes everything back to a fresh colony.
	MetaState.unlocked = ["repair_t2"]
	MetaState.seen_nudges = ["lair_intro"]
	MetaState.first_run_done = true
	MetaState.reset_new_game()
	_ck(MetaState.lair_stations.is_empty() and MetaState.discovered_recipes.is_empty(), "New Game clears the lair + recipe book")
	_ck(MetaState.unlocked.is_empty() and not MetaState.first_run_done and MetaState.seen_nudges.is_empty(), "New Game clears unlocks + onboarding flags")
	_ck(MetaState.colony_size() == 3, "New Game seeds a fresh 3-goblin colony")

	# Nudge gate: fires once, never twice, and goes quiet after the first run.
	_ck(MetaState.should_nudge("lair_intro"), "a first-time nudge fires")
	_ck(not MetaState.should_nudge("lair_intro"), "the same nudge never fires twice")
	MetaState.first_run_done = true
	_ck(not MetaState.should_nudge("deploy"), "no nudges once the first run is done")

	# Debug Lair pre-stocks a test game.
	MetaState.start_debug_lair()
	_ck(MetaState.debug_pending, "Debug Lair flags the in-world bootstrap")
	_ck(MetaState.colony_size() == 4, "Debug Lair seeds a 4-goblin colony")
	_ck(MetaState.has_tech("repair_t2") and MetaState.has_tech("tools_t2"), "Debug Lair unlocks a couple of techs")
	_ck(MetaState.first_run_done, "Debug Lair suppresses the guided nudges")

	MetaState.reset_new_game()   # leave the (restored) save clean

	if fail == 0:
		print("COLD_OPEN_TEST: ALL PASS")
	else:
		printerr("COLD_OPEN_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _quest(id: String) -> Dictionary:
	for q: Dictionary in GameData.quests:
		if String(q.get("id", "")) == id:
			return q
	return {}


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
