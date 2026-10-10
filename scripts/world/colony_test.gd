extends Node
## Slice 4 — the colony meta. The colony is a roster of NAMED goblins. A goblin lost in a siege
## is moved to the memorial for good (permadeath). You regrow the colony by RECRUITING at the
## System Terminal (spends banked Tech Data, climbing cost, capped at COLONY_MAX). The roster +
## memorial persist across runs. This drives that data model directly (no scene / physics).

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)  # tech data is a grid item now — need a factory
	# A fresh colony is a roster of distinctly-named goblins.
	MetaState.seed_colony(3)
	_ck(MetaState.colony_size() == 3, "a seeded colony has 3 goblins")
	_ck(MetaState.colony_names().size() == 3, "colony_names lists one name per goblin")
	_ck(_distinct(MetaState.colony_names()), "the goblins have distinct names (%s)" % ", ".join(MetaState.colony_names()))
	_ck(MetaState.fallen.is_empty(), "no goblins are fallen yet")

	# Hauls are credited to the named goblin (flavour + a meaningful memorial).
	var first := String(MetaState.colony_names()[0])
	MetaState.record_haul(first, 5)
	MetaState.record_haul(first, 2)
	_ck(_hauled_of(first) == 7, "%s is credited with the scrap it hauled (7)" % first)

	# Permadeath: losing a goblin moves it (with its stats) to the memorial, for good.
	var lost := MetaState.lose_goblin(first)
	_ck(MetaState.colony_size() == 2, "losing a goblin shrinks the colony to 2")
	_ck(int(lost.get("hauled", 0)) == 7, "the lost goblin keeps its haul record")
	_ck(MetaState.fallen.size() == 1 and String(MetaState.fallen[0].get("name", "")) == first, "%s is named in the memorial" % first)
	_ck(not MetaState.colony_names().has(first), "a fallen goblin never deploys again")

	# Losing an unknown name is a safe no-op.
	_ck(MetaState.lose_goblin("Nobody").is_empty(), "losing an unknown goblin does nothing")
	_ck(MetaState.colony_size() == 2, "the colony is untouched by a bad loss")

	# Recruiting: costs FOOD (gathered in runs), adds a freshly-named goblin, cost climbs.
	_ck(MetaState.recruit().is_empty(), "can't recruit with no Food")
	_ck(MetaState.colony_size() == 2, "a failed recruit adds no goblin")
	var cost2 := int(MetaState.recruit_cost().get("food", 0))
	RunState.add("food", cost2)
	var rec := MetaState.recruit()
	_ck(not rec.is_empty() and MetaState.colony_size() == 3, "recruiting adds a goblin (colony 3)")
	_ck(RunState.get_quantity("food") == 0, "recruiting spent the Food from the inventory")
	_ck(String(rec.get("name", "")) != first, "the recruit reuses no fallen name")
	_ck(int(MetaState.recruit_cost().get("food", 0)) > cost2, "the next recruit costs more Food (%d → %d)" % [cost2, int(MetaState.recruit_cost().get("food", 0))])

	# The colony is capped — you can't recruit past COLONY_MAX.
	RunState.add("food", 9999)
	while MetaState.can_recruit():
		MetaState.recruit()
	_ck(MetaState.colony_size() == MetaState.COLONY_MAX, "the colony fills to COLONY_MAX (%d)" % MetaState.COLONY_MAX)
	_ck(MetaState.recruit().is_empty(), "recruiting past the cap does nothing")

	# Persistence: the roster + memorial survive a save/load round-trip.
	MetaState.save_game()
	var snapshot := MetaState.colony_names()
	var dead := MetaState.fallen.size()
	MetaState.roster.clear()
	MetaState.fallen.clear()
	MetaState.load_game()
	_ck(MetaState.colony_names() == snapshot, "the roster reloads intact")
	_ck(MetaState.fallen.size() == dead, "the memorial reloads intact (%d fallen)" % dead)

	# Migration: a legacy save (a bare count, no roster) seeds a named roster on load.
	MetaState.roster.clear()
	MetaState.fallen.clear()
	MetaState.colony = 4
	MetaState.ensure_roster()
	_ck(MetaState.colony_size() == 4 and _distinct(MetaState.colony_names()), "a legacy colony count migrates to a named roster")

	MetaState.seed_colony(3)
	MetaState.save_game()
	if fail == 0:
		print("COLONY_TEST: ALL PASS")
	else:
		printerr("COLONY_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _distinct(names: Array) -> bool:
	var seen := {}
	for n: Variant in names:
		if seen.has(n):
			return false
		seen[n] = true
	return true


func _hauled_of(gob_name: String) -> int:
	for g: Dictionary in MetaState.roster:
		if String(g.get("name", "")) == gob_name:
			return int(g.get("hauled", 0))
	return -1


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
