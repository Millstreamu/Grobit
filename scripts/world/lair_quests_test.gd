extends Node
## The lair terminal's Tasks tab runs on colony QUESTS (data/game/quests.json): progress is read
## live from MetaState, a finished quest is CLAIMED once for a Tech Data reward, and the claim is
## permanent (idempotent). Also smoke-tests that LairPanel builds its Goblins/Tasks rows.

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	MetaState.quests_claimed = []
	MetaState.lair_needs = {}
	RunState.begin_run(GameData.first_area_id(), 1)  # Tech Data is a grid item — need a run inventory
	MetaState.seed_colony(3)

	_ck(GameData.quests.size() >= 1, "quests.json loaded (%d quests)" % GameData.quests.size())

	# Live progress: a "grow the colony to 6" quest reads the current roster size.
	var grow := _q("full_colony")
	_ck(not grow.is_empty(), "the full_colony quest exists")
	_ck(MetaState.quest_current(grow.get("goal", {})) == 3, "colony progress reads the roster (3)")
	_ck(not MetaState.quest_done(grow), "full_colony is not done at 3/6")

	# Fill the colony → the quest completes.
	RunState.add("tech_data", 9999)
	while MetaState.can_recruit():
		MetaState.recruit()
	_ck(MetaState.quest_done(grow), "full_colony is done once the colony is at max")

	# Claiming grants the reward once and only once.
	var before := RunState.get_quantity("tech_data")
	var reward := int(grow.get("reward", {}).get("tech_data", 0))
	_ck(MetaState.claim_quest(grow), "a finished quest can be claimed")
	_ck(RunState.get_quantity("tech_data") == before + reward, "claiming grants the Tech Data reward (+%d)" % reward)
	_ck(not MetaState.claim_quest(grow), "a claimed quest can't be claimed again")
	_ck(MetaState.quest_claimed("full_colony"), "the claim is recorded")

	# A need-based quest reads lair_needs; need_total spans all four needs.
	var seal := _q("first_seal")
	_ck(MetaState.quest_current(seal.get("goal", {})) == 0, "oxygen starts empty")
	MetaState.lair_needs["oxygen"] = MetaState.NEED_MAX
	_ck(MetaState.quest_done(seal), "first_seal completes when oxygen is full")
	var home := _q("homeward")
	_ck(not MetaState.quest_done(home), "homeward needs every lair need, not just one")

	# LairPanel smoke: its Goblins/Tasks row lists build without error.
	var panel := LairPanel.new()
	add_child(panel)
	_ck(panel._goblin_rows().size() == 1 + MetaState.colony_size(), "goblin rows = recruit + one per goblin")
	_ck(panel._quest_rows().size() == GameData.quests.size(), "Tasks tab lists one row per quest")
	var expected_upg := 1 + GameData.tech.size() + LairPanel.UPGRADABLE.size()
	_ck(panel._upgrade_rows().size() == expected_upg, "Upgrades tab = cargo + tech + machines (%d)" % expected_upg)
	panel.free()

	# Leave MetaState as we found it (in-memory; the sweep restores the save file).
	MetaState.quests_claimed = []
	MetaState.lair_needs = {}
	MetaState.machine_levels = {}

	if fail == 0:
		print("LAIR_QUESTS_TEST: ALL PASS")
	else:
		printerr("LAIR_QUESTS_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _q(id: String) -> Dictionary:
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
