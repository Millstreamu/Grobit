extends Node
## Scrap piles are harvested only by GOBLINS now (the scrapbot can't). take_one() pulls one piece
## and reports its id; the pile empties and frees when dry; it reports its tier; and it's never
## offerable to the player ([F]).

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	RunState.begin_run(GameData.first_area_id(), 1)  # bare grid

	var n := ScrapNode.new()
	n.generate({"tokens_min": 3, "tokens_max": 3, "pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(n)

	_ck(not n.can_interact(), "the scrapbot can't harvest a pile (not player-interactable)")
	_ck(n.scrap_tier() == 1, "a steel pile reports tier 1")

	# take_one pulls one piece and reports its id.
	_ck(n.take_one() == "steel_scrap" and n.tokens == 2, "take_one pulls a piece and spends a charge")

	# A goblin routing that through RunState.deposit feeds the grid.
	RunState.deposit(n.take_one(), 1)
	_ck(int(RunState.factory.resource_counts().get("steel_scrap", 0)) == 1, "a deposited piece feeds the grid")
	_ck(n.tokens == 1, "two pieces taken from the three-charge pile")

	# The last charge empties and frees the pile.
	n.take_one()
	_ck(n.is_spent() and n.is_queued_for_deletion(), "the emptied pile is spent and removed")

	# A dry pile yields nothing.
	_ck(n.take_one() == "", "a dry pile yields nothing")

	if fail == 0:
		print("SCRAP_NODE_TEST: ALL PASS")
	else:
		printerr("SCRAP_NODE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
